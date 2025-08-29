# Configure the Google Cloud Provider
terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Use existing Artifact Registry repository (deploy-flaskapp)
data "google_artifact_registry_repository" "app_repo" {
  location      = var.region
  repository_id = var.artifact_registry_repo
}

# Use existing service accounts instead of creating new ones
data "google_service_account" "cloudrun_sa" {
  account_id = "${var.app_name}-cloudrun-sa"
}

data "google_service_account" "invoker_sa" {
  account_id = "${var.app_name}-invoker-sa"
}

# Use existing VPC connector
data "google_vpc_access_connector" "connector" {
  name   = "${var.app_name}-connector"
  region = var.region
}

# Cloud Run service (this might need to be created or updated)
resource "google_cloud_run_v2_service" "app_service" {
  name     = var.app_name
  location = var.region

  template {
    service_account = data.google_service_account.cloudrun_sa.email

    scaling {
      min_instance_count = 0
      max_instance_count = 10
    }

    # VPC Access for internal networking
    vpc_access {
      connector = data.google_vpc_access_connector.connector.id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_registry_repo}/${var.app_name}:${var.image_tag}"

      ports {
        container_port = 8080
      }

      # Custom environment variables only (PORT is reserved by Cloud Run)
      env {
        name  = "ENVIRONMENT"
        value = "production"
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = true
        startup_cpu_boost = false
      }

      startup_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 10
        timeout_seconds       = 5
        period_seconds        = 10
        failure_threshold     = 3
      }

      liveness_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 15
        timeout_seconds       = 5
        period_seconds        = 10
        failure_threshold     = 3
      }
    }
  }

  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }
}

# SECURITY: Configure Cloud Run for internal access only
# Grant access only to specific service account (not allUsers)
resource "google_cloud_run_v2_service_iam_member" "invoker_access" {
  project  = var.project_id
  location = google_cloud_run_v2_service.app_service.location
  name     = google_cloud_run_v2_service.app_service.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${data.google_service_account.invoker_sa.email}"
}