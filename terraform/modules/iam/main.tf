resource "google_service_account" "workload" {
  project      = var.project_id
  account_id   = var.gsa_account_id
  display_name = "Atlas Workload Platform Service Account"
}

resource "google_service_account_iam_member" "workload_identity_binding" {
  service_account_id = google_service_account.workload.name
  role                = "roles/iam.workloadIdentityUser"
  member              = "serviceAccount:${var.project_id}.svc.id.goog[${var.ksa_namespace}/${var.ksa_name}]"
}

resource "google_project_iam_member" "workload_artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.workload.email}"
}
