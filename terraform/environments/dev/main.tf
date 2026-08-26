module "network" {
  source = "../../modules/network"

  project_id = var.project_id
  region     = var.region
}

module "gke" {
  source = "../../modules/gke"

  project_id           = var.project_id
  zone                 = var.zone
  network_name         = module.network.network_name
  subnet_name          = module.network.subnet_name
  pods_range_name      = module.network.pods_range_name
  services_range_name  = module.network.services_range_name
}

module "artifact_registry" {
  source = "../../modules/artifact-registry"

  project_id = var.project_id
  region     = var.region
}

module "iam" {
  source = "../../modules/iam"

  project_id = var.project_id
}
