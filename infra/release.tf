# Séance 6, « Après le TD » : l'abonnement d'ombre et la règle d'alerte de votre équipe.
# Copié depuis docs/seance-6/release.tf. Il utilise var.team, var.project_id et var.region de infra/variables.tf.
# Les trois choix de la règle d'alerte sont repérés par (1), (2) et (3).

variable "shadow_tag" {
  description = "Tag de la révision qui reçoit l'ombre (candidate, degrade...). Vide : pas d'abonnement d'ombre."
  type        = string
  default     = ""
}

data "google_cloud_run_v2_service" "scorer" {
  name     = "${var.team}-scorer"
  location = var.region
}

locals {
  shadow_url = one([
    for t in data.google_cloud_run_v2_service.scorer.traffic_statuses : t.uri if t.tag == var.shadow_tag
  ])
}

# Mêmes réglages que shadow.sh. L'audience est l'adresse du service, pas celle du tag.
resource "google_pubsub_subscription" "shadow" {
  count = var.shadow_tag == "" ? 0 : 1

  name  = "${var.team}-shadow"
  topic = "projects/${var.project_id}/topics/ff-td6"

  ack_deadline_seconds       = 30
  message_retention_duration = "3600s"

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "60s"
  }

  push_config {
    push_endpoint = "${local.shadow_url}/pubsub/shadow"

    oidc_token {
      service_account_email = "${var.team}-scorer-push@${var.project_id}.iam.gserviceaccount.com"
      audience              = data.google_cloud_run_v2_service.scorer.uri
    }
  }

  lifecycle {
    precondition {
      condition     = local.shadow_url != null
      error_message = "Le tag ${var.shadow_tag} n'existe pas sur ${var.team}-scorer."
    }
  }
}

# Le projet n'a pas de canal de notification : la règle ouvre un incident dans Monitoring → Alertes.
resource "google_monitoring_alert_policy" "release" {
  display_name = "${var.team}-scorer-release"
  combiner     = "OR"

  user_labels = {
    team = var.team
  }

  conditions {
    display_name = "${var.team}-scorer, par révision"

    condition_threshold {
      # (1) Signal : les messages en échec (td6_failed), comptés par révision et par minute. C'est le
      # seul signal qui a vu la panne de next : elle n'a scoré aucune transaction, donc ni latence
      # ni score n'étaient disponibles.
      filter = "metric.type=\"logging.googleapis.com/user/td6_failed\" AND resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"${var.team}-scorer\""

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.label.revision_name"]
      }

      comparison = "COMPARISON_GT"

      # (2) Seuil : plus de 10 échecs par minute sur une révision. En temps normal, il y en a 0
      # (aucun td6_failed pour candidate ni champion pendant toute la séance) ; pendant la panne,
      # next en a compté 23 la première minute, puis 55 à 75 par minute.
      threshold_value = 10

      # (3) Durée : seuil franchi pendant 60 s, pour qu'un échec isolé n'ouvre pas la règle.
      duration = "60s"

      trigger {
        count = 1
      }
    }
  }
}
