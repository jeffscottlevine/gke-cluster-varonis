variable "project_id" {
  type = string
  nullable = false
  description = "The ID of the project for the bastion host and the GKE cluster"
}

variable "gcp_service_list" {
  description ="The list of apis necessary for the project"
  type = list(string)
  default = [
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "iap.googleapis.com",
    "logging.googleapis.com",
    "oslogin.googleapis.com",
    "serviceusage.googleapis.com"
  ]
}
