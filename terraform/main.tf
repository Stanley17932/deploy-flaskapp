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

# Use existing Cloud Run service
data "google_cloud_run_v2_service" "app_service" {
  name     = var.app_name
  location = var.region
}

# SECURITY: Configure Cloud Run for internal access only
# Grant access only to specific service account (not allUsers)
resource "google_cloud_run_v2_service_iam_member" "invoker_access" {
  project  = var.project_id
  location = data.google_cloud_run_v2_service.app_service.location
  name     = data.google_cloud_run_v2_service.app_service.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${data.google_service_account.invoker_sa.email}"
}

# NEW: Grant CI/CD service account access for testing
# Extract service account email from the GCP_SA_KEY secret
# This assumes your CI/CD service account follows standard naming
locals {
  # Extract project ID for service account email construction
  cicd_sa_email = var.enable_cicd_access ? "github-actions-sa@${var.project_id}.iam.gserviceaccount.com" : null
}

resource "google_cloud_run_v2_service_iam_member" "cicd_invoker_access" {
  count    = var.enable_cicd_access ? 1 : 0
  project  = var.project_id
  location = data.google_cloud_run_v2_service.app_service.location
  name     = data.google_cloud_run_v2_service.app_service.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${local.cicd_sa_email}"
}