terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = ">=7.0.0"
    }
    time = {
      source = "hashicorp/time"
      version = ">= 0.13.0" # Specify a suitable version
    }
  }
}

provider "google" {
  project = var.project_id
  region = var.region
  zone = var.bastion_zone
}
