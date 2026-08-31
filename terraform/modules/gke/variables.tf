variable "project_id" {
  type = string
}

variable "zone" {
  type = string
}

variable "cluster_name" {
  type    = string
  default = "atlas-dev"
}

variable "network_name" {
  type = string
}

variable "subnet_name" {
  type = string
}

variable "pods_range_name" {
  type = string
}

variable "services_range_name" {
  type = string
}

variable "node_count" {
  type    = number
  default = 2
}

variable "machine_type" {
  type    = string
  default = "e2-standard-4"
}

variable "disk_size_gb" {
  type    = number
  default = 30
}
