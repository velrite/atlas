variable "project_id" {
  type = string
}

variable "gsa_account_id" {
  type    = string
  default = "atlas-workload"
}

variable "ksa_namespace" {
  type    = string
  default = "atlas-platform"
}

variable "ksa_name" {
  type    = string
  default = "atlas-workload-ksa"
}
