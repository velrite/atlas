resource "google_artifact_registry_repository" "atlas" {
  project       = var.project_id
  location      = var.region
  repository_id = var.repository_id
  description   = "Container images for Atlas platform components"
  format        = "DOCKER"
}
