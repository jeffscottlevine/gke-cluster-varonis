variable "project_id" {
  type = string
  description = "The ID of the project for the bastion host and the GKE cluster"
}

variable "subnet_range" {
  type = string
  default = "10.100.16.0/20"
  description = "The IP range of the Varonis subnet for the bastion and cluster nodes"
}

variable "create_bastion_host" {
  type = bool
  default = false
  description = "Create a bastion host (default=false)?"
}

variable "bastion_machine_type" {
  type = string
  default = "e2-medium"
  description = "The machine type of the bastion host"
}

variable "bastion_image_project" {
  type = string
  default = "ubuntu-os-cloud"
  description = "The project for the bastion host image"
}

variable "bastion_image_family" {
  type = string
  default = "ubuntu-2404-lts-amd64"
  description = "The family for the bastion host image"
}

variable "gke_image_type" {
  type = string
  default = "UBUNTU_CONTAINERD"
  description = "The image type for the GKE nodes"
}

variable "bastion_zone" {
  type = string
  default = "us-central1-a"
  description = "The zone for the bastion host"
}

variable "gke_location" {
  type = string
  default = "us-central1-a"
  description = "The location for the cluster, either a zone or a region"
}
variable "gke_machine_type" {
  type = string
  default = "n2-standard-8"
  description = "The machine type for the GKE nodes"
}

variable "gke_node_count" {
  type = number
  default = 2
  description = "The number of nodes in the GKE cluster per zone"
}

variable "gke_node_disk_size_gb" {
  type = number
  default = 40
  description = "The amount of storage per GKE node in GB"
}

variable "gke_node_disk_type" {
  type = string
  default = "pd-standard"
  description = "The storage type for each  GKE node"
}

variable "gke_node_maint_start" {
  type=string
  default = "2025-09-01T09:00:00Z"
  description = "Start of GKE maintenance windows in RFC3339 zulu format"
}

variable "gke_node_maint_end" {
  type=string
  default = "2025-09-30T12:00:00Z"
  description = "End of GKE maintenance windows in RFC3339 zulu format"
}

variable "gke_node_maint_recurrence" {
  type=string
  default = "FREQ=WEEKLY;BYDAY=SA,SU"
  description = "GKE maintenance window recurrence in RFC5545 RRULE format"
}

variable "region" {
  type = string
  default = "us-central1"
  description = "The region for the bastion host and GKE cluster"
}
