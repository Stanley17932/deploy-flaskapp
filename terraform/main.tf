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

# Enable required APIs
resource "google_project_service" "cloudrun_api" {
  project = var.project_id
  service = "run.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

resource "google_project_service" "artifact_registry_api" {
  project = var.project_id
  service = "artifactregistry.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

resource "google_project_service" "cloudbuild_api" {
  project = var.project_id
  service = "cloudbuild.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

resource "google_project_service" "iam_api" {
  project = var.project_id
  service = "iam.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

resource "google_project_service" "vpcaccess_api" {
  project = var.project_id
  service = "vpcaccess.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

# Use existing Artifact Registry repository (deploy-flaskapp)
data "google_artifact_registry_repository" "app_repo" {
  location      = var.region
  repository_id = var.artifact_registry_repo

  depends_on = [google_project_service.artifact_registry_api]
}

# Create service account for Cloud Run
resource "google_service_account" "cloudrun_sa" {
  account_id   = "${var.app_name}-cloudrun-sa"
  display_name = "Cloud Run Service Account for ${var.app_name}"
  description  = "Service account for running the text analyzer Cloud Run service"
}

# Grant minimal permissions to service account
resource "google_project_iam_member" "cloudrun_sa_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloudrun_sa.email}"
}

resource "google_project_iam_member" "cloudrun_sa_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.cloudrun_sa.email}"
}

# Create invoker service account for accessing the service
resource "google_service_account" "invoker_sa" {
  account_id   = "${var.app_name}-invoker-sa"
  display_name = "Service Account for invoking ${var.app_name}"
  description  = "Service account with permission to invoke the text analyzer service"
}

# Cloud Run service
resource "google_cloud_run_v2_service" "app_service" {
  name     = var.app_name
  location = var.region

  depends_on = [
    google_project_service.cloudrun_api,
    google_service_account.cloudrun_sa
  ]

  template {
    service_account = google_service_account.cloudrun_sa.email

    scaling {
      min_instance_count = 0
      max_instance_count = 10
    }

    # VPC Access for internal networking
    vpc_access {
      connector = google_vpc_access_connector.connector.id
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
  member   = "serviceAccount:${google_service_account.invoker_sa.email}"
}

# VPC connector for secure networking
resource "google_vpc_access_connector" "connector" {
  name          = "${var.app_name}-connector"
  region        = var.region
  ip_cidr_range = "10.8.0.0/28"
  network       = "default"

  depends_on = [
    google_project_service.cloudrun_api,
    google_project_service.vpcaccess_api
  ]
}