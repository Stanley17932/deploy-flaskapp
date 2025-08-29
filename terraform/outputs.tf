output "cloud_run_url" {
  description = "URL of the deployed Cloud Run service"
  value       = data.google_cloud_run_v2_service.app_service.uri
}

output "artifact_registry_repo_url" {
  description = "URL of the Artifact Registry repository"
  value       = data.google_artifact_registry_repository.app_repo.name
}

output "service_account_email" {
  description = "Email of the Cloud Run service account"
  value       = data.google_service_account.cloudrun_sa.email
}

output "invoker_service_account_email" {
  description = "Email of the invoker service account"
  value       = data.google_service_account.invoker_sa.email
}

output "project_id" {
  description = "The GCP project ID"
  value       = var.project_id
}

output "region" {
  description = "The GCP region"
  value       = var.region
}