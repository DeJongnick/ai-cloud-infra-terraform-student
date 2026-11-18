# Séance 4, partie D : une base vectorielle (Qdrant) sur Cloud Run, pour les justificatifs KYC.
# Version complétée par team3, retirée de infra/ après les mesures pour arrêter le service (coût permanent).
# Pour la recréer : cp docs/seance-4/team3-vectors.tf infra/vectors.tf, puis terraform apply.

resource "google_cloud_run_v2_service" "vectors" {
  name                = "${var.team}-vectors"
  location            = var.region
  deletion_protection = false

  template {
    scaling {
      # (a) L'index vit dans la mémoire d'une seule instance : elle ne doit ni s'arrêter (min 1)
      #     ni être doublée par une autre qui aurait une mémoire vide (max 1).
      min_instance_count = 1
      max_instance_count = 1
    }

    containers {
      image = "docker.io/qdrant/qdrant:v1.12.4"

      ports {
        container_port = 6333
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "2Gi"
        }
        cpu_idle = false
      }
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "vectors_invokers" {
  for_each = toset(var.invokers)
  name     = google_cloud_run_v2_service.vectors.name
  location = var.region
  # (b) Le droit d'appeler un service Cloud Run privé.
  role   = "roles/run.invoker"
  member = each.value
}

output "vectors_url" {
  value = google_cloud_run_v2_service.vectors.uri
}
