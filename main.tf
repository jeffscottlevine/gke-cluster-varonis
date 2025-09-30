# random_suffix - a four character random suffix used to add randomness to
# Google Cloud resource identifiers.  This helps in the event that additional
# Terraform deployments are needed in the same project.

resource "random_string" "random_suffix" {
  length = 4
  special = false
  lower = true
  upper = false
  numeric = true
}

# Create network resources
#
# The following resources will be deployed:
#
# 1. A VPC network
# 2. A subnet in the VPC network
# 3. A firewall rule to grant the Google Cloud Identity-Aware Proxy
#    the ability to support SSH connections to the bastion host
# 4. A static IP address
# 5. A cloud router
# 6. Cloud NAT to provide internet egress to the GKE cluster and the
#    bastion host.

resource "google_compute_network" "vpc_network" {
  name = "varonis-vpc-${random_string.random_suffix.result}"
  description = "VPC for the resources for the IAP demo"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "vpc_subnet" {
  name = "varonis-subnet-${random_string.random_suffix.result}"
  description = "Subnet for the server and cluster for the VPC"
  ip_cidr_range = var.subnet_range
  region = var.region
  network = google_compute_network.vpc_network.id
}

resource "google_compute_address" "nat_ip" {
  name   = "varonis-nat-ip-${random_string.random_suffix.result}"
  region = google_compute_subnetwork.vpc_subnet.region
}

resource "google_compute_router" "vpc_router" {
  name = "varonis-router-${random_string.random_suffix.result}"
  region = google_compute_subnetwork.vpc_subnet.region
  network = google_compute_network.vpc_network.id
}

resource "google_compute_router_nat" "nat" {
  name = "varonis-nat-${random_string.random_suffix.result}"
  router = google_compute_router.vpc_router.name
  region = google_compute_router.vpc_router.region
  nat_ip_allocate_option = "MANUAL_ONLY"
  nat_ips = [google_compute_address.nat_ip.self_link]
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# GKE service account roles
#
# Default Node Servie Account - needed for GKE nodes
# Serice Account Tolen Creator - needed for Container Threat Detection
# Metrics Writer - needed for horizontal pod autoscaling (HPA)

locals {
  google_cloud_gke_sa_roles = toset([
    "roles/container.defaultNodeServiceAccount",
    "roles/iam.serviceAccountTokenCreator",
    "roles/autoscaling.metricsWriter"
  ])
}

resource "google_service_account" "gke_sa" {
  account_id = "varonis-gke-sa-${random_string.random_suffix.result}"
  display_name = "Varonis GKE service account"
}

resource "google_project_iam_member" "gke_service_account_iam_member" {
  project = var.project_id

  for_each = local.google_cloud_gke_sa_roles

  role = each.key
  member = "serviceAccount:${google_service_account.gke_sa.email}"
}

# get_gke_cluster_creds
#
# Create a local variable to hold the command used to fetch the GKE cluster
# credentials.  We use this in the output and also in the bastion host

locals {
  get_gke_cluster_creds = join(" ", [
            "gcloud container clusters get-credentials",
            google_container_cluster.gke_cluster.name,
            "--dns-endpoint --location",
            google_container_cluster.gke_cluster.location
  ])
}

resource "google_container_cluster" "gke_cluster" {
  name = "varonis-gke-cluster-${random_string.random_suffix.result}"

  location = var.gke_location
  network = google_compute_network.vpc_network.self_link
  subnetwork = google_compute_subnetwork.vpc_subnet.self_link 

  initial_node_count = var.gke_node_count

  private_cluster_config {
    enable_private_nodes = true
    enable_private_endpoint = true
  }

  release_channel {
    channel = "REGULAR"
  }

  control_plane_endpoints_config {
    ip_endpoints_config {
      enabled = false
    }
    dns_endpoint_config {
      allow_external_traffic = true
    }
  }

  monitoring_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "HPA"
    ]
  }

  logging_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "WORKLOADS"
    ]
  }

  maintenance_policy {
    recurring_window {
      start_time = var.gke_node_maint_start
      end_time = var.gke_node_maint_end
      recurrence = var.gke_node_maint_recurrence
    }
  }

  node_config {
    preemptible = false
    machine_type = var.gke_machine_type

    image_type = var.gke_image_type
    disk_size_gb = var.gke_node_disk_size_gb
    disk_type = var.gke_node_disk_type

    metadata = {
      disable-legacy-endpoints = "true"
    }
   
    service_account = resource.google_service_account.gke_sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
 
  depends_on = [ google_compute_router_nat.nat ]

  deletion_protection = false
}

# Create a bastion host
#
# A bastion host might be desireable if your local workstation does not have
# utilities such as helm, kubectl, and the Google Cloud CLI. A bastion host
# can also help with loading data with tools such as the Postgres client.

resource "google_compute_firewall" "fw_tunneled_ssh_traffic" {
  count = var.create_bastion_host ? 1 : 0
  name = "varonis-fw-iap-ssh-traffic-${random_string.random_suffix.result}"

  network = google_compute_network.vpc_network.name
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports = ["22"]
  }

  source_ranges = [ "35.235.240.0/20" ]
}

data "google_compute_image" "bastion_host_image" {
  provider = google

  family = var.bastion_image_family
  project = var.bastion_image_project
}

resource "google_service_account" "bastion_sa" {
  count = var.create_bastion_host ? 1 : 0
  account_id = "varonis-bastion-sa-${random_string.random_suffix.result}"
  display_name = "Varonis bastion service account"
}

resource "google_project_iam_member" "bastion_service_account_iam_member" {
  count = var.create_bastion_host ? 1 : 0
  project = var.project_id
  role = "roles/container.admin"
  member = "serviceAccount:${google_service_account.bastion_sa[0].email}"
}

# Set up bastion host

# bastion-host-template - instance template for creating a bastion host
# 
# startup-script - Metadata key containing startup shell script
# enable-oslogin - Metadata key to enable OS Login
#
# Notes:
#
# The startup SCRIPT heredoc begins with "<<-" to strip off leading spaces.
# If you remove the "-" from "<<-", the heredoc will include the leading
# spaces and will not load properly.

resource "google_compute_instance_template" "bastion_host_template" {
  count = var.create_bastion_host ? 1 : 0
  name = "varonis-bastion-template-${random_string.random_suffix.result}"
  description = "Instance template for the bastion host server"
  region = var.region
  machine_type = var.bastion_machine_type

  network_interface {
    subnetwork = google_compute_subnetwork.vpc_subnet.self_link
  }

  shielded_instance_config {
    enable_secure_boot = true
  }

  disk {
    boot = true
    source_image = data.google_compute_image.bastion_host_image.self_link
    disk_type = "pd-standard"
  }

  service_account {
    email  = google_service_account.bastion_sa[0].email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
    startup-script = <<-SCRIPT
      #!/bin/bash

      # Remove the pre-installed Google Cloud SDK snap package since it makes
      # it more difficult to install newer versions of the Google Cloud SDK,
      # kubectl, and helm.

      snap remove google-cloud-sdk
      snap remove google-cloud-cli

      # Install the most recent version of the Google Cloud sdk

      sudo apt-get update -y
      sudo apt-get -y install apt-transport-https ca-certificates gnupg curl
      curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
      echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
      apt-get update -y && sudo apt-get install -y google-cloud-cli
      apt-get install -y google-cloud-sdk-gke-gcloud-auth-plugin

      # Install kubectl, unzip, and the gh (GitHub) command line

      apt-get install -y kubectl
      apt-get install -y unzip
      apt-get install -y gh

      # Install the Postgres client

      apt-get install -y postgresql-client-common
      apt-get install -y postgresql-client

      # Install helm

      curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
      chmod 700 get_helm.sh
      ./get_helm.sh

      # Create /tmp/get_gke_creds to make it easier to fetch the GKE cluster
      # credentials

      GET_CREDS_CMD="${local.get_gke_cluster_creds}"
      echo $GET_CREDS_CMD>/tmp/get_gke_creds
      chmod 755 /tmp/get_gke_creds
    SCRIPT
  }
}

resource "google_compute_instance_from_template" "bastion_host" {
  count = var.create_bastion_host ? 1 : 0
  name = "varonis-bastion-${random_string.random_suffix.result}"
  description = "Varonis bastion host"

  zone = var.bastion_zone
  source_instance_template = (
    google_compute_instance_template.bastion_host_template[0].id
  )

  depends_on = [ google_compute_router_nat.nat ]
}
