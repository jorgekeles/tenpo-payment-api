output "load_balancer_ip" {
  value       = module.service.load_balancer_ip
  description = "The public IP of the external Application HTTPS Load Balancer"
}

output "cloud_run_url" {
  value       = module.service.cloud_run_url
  description = "The internal URL of the Cloud Run service"
}

output "pubsub_topic_id" {
  value       = module.data_pipeline.pubsub_topic_id
  description = "The ID of the Pub/Sub topic created for payment events"
}