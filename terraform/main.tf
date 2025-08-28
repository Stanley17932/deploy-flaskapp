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

# Create Artifact Registry repository
resource "google_artifact_registry_repository" "app_repo" {
  location      = var.region
  repository_id = var.artifact_registry_repo
  description   = "Repository for text analyzer application images"
  format        = "DOCKER"

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

    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_registry_repo}/${var.app_name}:${var.image_tag}"
      
      ports {
        container_port = 8080
      }

      env {
        name  = "PORT"
        value = "8080"
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle = true
        startup_cpu_boost = false
      }

      startup_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 10
        timeout_seconds      = 5
        period_seconds       = 10
        failure_threshold    = 3
      }

      liveness_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 15
        timeout_seconds      = 5
        period_seconds       = 10
        failure_threshold    = 3
      }
    }
  }

  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }
}

# Configure Cloud Run to allow internal traffic only
resource "google_cloud_run_v2_service_iam_member" "internal_access" {
  project  = var.project_id
  location = google_cloud_run_v2_service.app_service.location
  name     = google_cloud_run_v2_service.app_service.name
  role     = "roles/run.invoker"
  member   = "allUsers"
  
  # Note: In a production environment, you would restrict this further
  # For example, to specific service accounts or VPC networks
  # member = "serviceAccount:${var.invoker_service_account_email}"
}

# Create a VPC connector for private networking (optional but recommended)
resource "google_vpc_access_connector" "connector" {
  name          = "${var.app_name}-connector"
  region        = var.region
  ip_cidr_range = "10.8.0.0/28"
  network       = "default"
  
  depends_on = [google_project_service.cloudrun_api]
}