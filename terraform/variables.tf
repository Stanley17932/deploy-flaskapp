variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "app_name" {
  description = "Name of the application"
  type        = string
  default     = "text-analyzer"
}

variable "artifact_registry_repo" {
  description = "Name of the Artifact Registry repository"
  type        = string
  default     = "deploy-flaskapp"
}

variable "image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

variable "enable_cicd_access" {
  description = "Enable Cloud Build service account access for CI/CD"
  type        = bool
  default     = true
}