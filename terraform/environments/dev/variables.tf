variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "Primary GCP region for dev environment"
  type        = string
  default     = "us-central1"
}
