# Séance 6, « Après le TD » : description du service team3-scorer, qui appartient au socle.
# État local, sans backend. Dans ce dossier : terraform plan seulement, jamais apply ni destroy.

terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0"
    }
  }
}

provider "google" {
  project = "advanced-cloud-ai"
  region  = "europe-west1"

  add_terraform_attribution_label = false
}

import {
  to = google_cloud_run_v2_service.scorer
  id = "projects/advanced-cloud-ai/locations/europe-west1/services/team3-scorer"
}
