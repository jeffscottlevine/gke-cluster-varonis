output "Random_suffix" {
  value = random_string.random_suffix.result
}

output "NAT_ip" {
  value = google_compute_address.nat_ip.address
}

output "GKE_cluster_DNS_endpoint" {
  value = google_container_cluster.gke_cluster.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint
}

output "GKE_cluster_get_creds" {
  value = local.get_gke_cluster_creds
}

output "GKE_cluster_name" {
  value = google_container_cluster.gke_cluster.name
}

output "Bastion_host_instance_id" {
  value = (
    var.create_bastion_host
      ? google_compute_instance_from_template.bastion_host[0].name
      : "Not Applicable"
  )
}

output "Bastion_ssh" {
  value = (
    var.create_bastion_host
      ? join(" ", [
          "gcloud compute ssh --zone",
          google_compute_instance_from_template.bastion_host[0].zone,
          google_compute_instance_from_template.bastion_host[0].name,
          "--tunnel-through-iap --project",
          var.project_id
        ])
      : "Not Applicable"
  )
}

output "ZZZ_SSH_Msg" {
  value = <<-EOF
    *********************************************************************
    *                                                                   *
    * Please grant the IAM role below to users at the orgination or     *
    * project level of the resource hierarchy to enable users to SSH    *
    * into the GKE nodes and optional bastion host.                     *
    *                                                                   *
    * IAP-secured Tunnel User (roles/iap.tunnelResourceAccessor)        *
    *                                                                   *
    *********************************************************************
    EOF
}
