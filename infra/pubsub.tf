# Identity used by Pub/Sub to authenticate push requests to the private service.
resource "google_service_account" "push" {
  account_id   = "${var.team}-push"
  display_name = "Livraison Pub/Sub vers le service de scoring ${var.team}"
}

resource "google_service_account_iam_member" "pubsub_token_creator" {
  service_account_id = google_service_account.push.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_cloud_run_v2_service_iam_member" "push_invokes_api" {
  name     = google_cloud_run_v2_service.api.name
  location = var.region
  role     = "roles/run.invoker"
  member   = google_service_account.push.member
}

resource "google_pubsub_topic" "dead" {
  name = "${var.team}-tx-dead"
}

resource "google_pubsub_subscription" "dead_pull" {
  name  = "${var.team}-tx-dead-pull"
  topic = google_pubsub_topic.dead.id
}

resource "google_pubsub_subscription" "tx" {
  name                       = "${var.team}-tx-push"
  topic                      = var.tx_topic
  ack_deadline_seconds       = 30
  message_retention_duration = "3600s"

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

output "push_subscription" {
  value = google_pubsub_subscription.tx.name
}

output "dead_letter_subscription" {
  value = google_pubsub_subscription.dead_pull.name
}
