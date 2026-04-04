terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_project_service" "container" {
  service = "container.googleapis.com"
}

resource "google_project_service" "compute" {
  service = "compute.googleapis.com"
}

resource "google_container_cluster" "ci" {
  name     = "ci-cluster"
  location = var.region

  enable_autopilot = true
  release_channel {
    channel = "REGULAR"
  }

  deletion_protection = false

  depends_on = [
    google_project_service.container,
    google_project_service.compute,
  ]
}
