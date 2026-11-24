# Démonstration de la soutenance : un topic à nous, branché sur le même /pubsub que ff-tx.
# On ne peut pas publier dans ff-tx (topic de l'enseignant) ; ce topic permet de publier
# une transaction, puis un message empoisonné, et de les suivre en direct.
# Même compte de livraison (team3-push, seul droit run.invoker), même file de messages
# morts, même politique de relivraison que team3-tx-push : aucun droit nouveau.

resource "google_pubsub_topic" "demo" {
  name                       = "${var.team}-demo"
  message_retention_duration = "600s"

  labels = {
    team = var.team
  }
}

resource "google_pubsub_subscription" "demo" {
  name                       = "${var.team}-demo-push"
  topic                      = google_pubsub_topic.demo.id
  ack_deadline_seconds       = 30
  message_retention_duration = "600s"

  push_config {
    push_endpoint = "${google_cloud_run_v2_service.api.uri}/pubsub"

    oidc_token {
      service_account_email = google_service_account.push.email
      audience              = google_cloud_run_v2_service.api.uri
    }
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "60s"
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead.id
    max_delivery_attempts = 5
  }

  labels = {
    team = var.team
  }

  depends_on = [
    google_cloud_run_v2_service_iam_member.push_invokes_api,
    google_service_account_iam_member.pubsub_token_creator,
  ]
}

output "demo_topic" {
  value = google_pubsub_topic.demo.name
}
