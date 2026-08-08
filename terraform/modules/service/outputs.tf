output "load_balancer_ip" {
  value       = google_compute_global_forwarding_rule.http.ip_address
  description = "The public IP of the external Application Load Balancer"
}

output "cloud_run_url" {
  value       = google_cloud_run_v2_service.payment_api.uri
  description = "The internal URL of the Cloud Run service"
}

output "service_account_email" {
  value       = google_service_account.service_sa.email
  description = "The email of the Service Account running Cloud Run"
}