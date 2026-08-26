terraform {
  backend "gcs" {
    bucket                      = "velrite-tf-test-atlas-tfstate"
    prefix                      = "dev"
    impersonate_service_account = "atlas-terraform@velrite-tf-test.iam.gserviceaccount.com"
  }
}
