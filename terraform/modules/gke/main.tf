resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  project  = var.project_id
  location = var.zone

  network    = var.network_name
  subnetwork = var.subnet_name

  remove_default_node_pool = true
  initial_node_count       = 1

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  deletion_protection = false
}

resource "google_container_node_pool" "primary_nodes" {
  name     = "${var.cluster_name}-pool"
  project  = var.project_id
  location = var.zone
  cluster  = google_container_cluster.primary.name

  node_count = var.node_count

  node_config {
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb
    disk_type    = "pd-balanced"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = {
      environment = "dev"
      project     = "atlas"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
