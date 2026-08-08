output "pubsub_topic_name" {
  value       = google_pubsub_topic.payment_events.name
  description = "The name of the Pub/Sub topic"
}

output "pubsub_topic_id" {
  value       = google_pubsub_topic.payment_events.id
  description = "The ID of the Pub/Sub topic"
}

output "bigquery_dataset_id" {
  value       = google_bigquery_dataset.analytics.dataset_id
  description = "The ID of the BigQuery dataset"
}

output "bigquery_table_id" {
  value       = google_bigquery_table.payment_transactions.table_id
  description = "The ID of the BigQuery table"
}