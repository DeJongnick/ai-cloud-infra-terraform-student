# l'URL du service et l'adresse du compte de service d'exécution.
output "service_url" {
  description = "URL du service Cloud Run."
  value       = google_cloud_run_v2_service.api.uri
}

output "service_account_email" {
  description = "Adresse du compte de service d'exécution."
  value       = google_service_account.run.email
}