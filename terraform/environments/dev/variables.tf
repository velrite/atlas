variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "Primary GCP region for dev environment"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Zone for the dev GKE cluster (zonal, not regional, to avoid the control-plane HA management fee)"
  type        = string
  default     = "us-central1-a"
}
