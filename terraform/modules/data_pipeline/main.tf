data "google_project" "project" {}

# 1. Pub/Sub Topic for transaction events
resource "google_pubsub_topic" "payment_events" {
  name = "tenpo-payment-events-${var.environment}"

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

# 2. BigQuery Dataset for analytical ingestion
resource "google_bigquery_dataset" "analytics" {
  dataset_id                  = "tenpo_analytics_${var.environment}"
  friendly_name               = "Tenpo Analytics Dataset"
  description                 = "Dataset for payment transaction events ingestion"
  location                    = var.region
  default_table_expiration_ms = 31536000000 # 1 year in ms

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

# 3. BigQuery Table for structured transaction data
resource "google_bigquery_table" "payment_transactions" {
  dataset_id          = google_bigquery_dataset.analytics.dataset_id
  table_id            = "payment_transactions"
  deletion_protection = false # Enabled/disabled for safety in challenges

  schema = <<EOF
[
  {
    "name": "transaction_id",
    "type": "STRING",
    "mode": "REQUIRED",
    "description": "Unique transaction ID"
  },
  {
    "name": "user_id",
    "type": "STRING",
    "mode": "REQUIRED",
    "description": "User identifier"
  },
  {
    "name": "amount",
    "type": "NUMERIC",
    "mode": "REQUIRED",
    "description": "Transaction amount"
  },
  {
    "name": "currency",
    "type": "STRING",
    "mode": "REQUIRED",
    "description": "Currency code (e.g. CLP, USD)"
  },
  {
    "name": "status",
    "type": "STRING",
    "mode": "REQUIRED",
    "description": "Transaction status (SUCCESS, FAILED)"
  },
  {
    "name": "created_at",
    "type": "TIMESTAMP",
    "mode": "REQUIRED",
    "description": "Transaction timestamp"
  }
]
EOF
}

# 4. IAM Permissions for Pub/Sub Service Identity to write into BigQuery
resource "google_bigquery_dataset_iam_member" "pubsub_metadata" {
  dataset_id = google_bigquery_dataset.analytics.dataset_id
  role       = "roles/bigquery.metadataViewer"
  member     = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_bigquery_dataset_iam_member" "pubsub_data_editor" {
  dataset_id = google_bigquery_dataset.analytics.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# 5. Pub/Sub to BigQuery Direct Subscription
resource "google_pubsub_subscription" "bq_ingest" {
  name  = "tenpo-payment-bq-sub-${var.environment}"
  topic = google_pubsub_topic.payment_events.name

  bigquery_config {
    table                   = "${var.project_id}:${google_bigquery_table.payment_transactions.dataset_id}.${google_bigquery_table.payment_transactions.table_id}"
    use_topic_schema        = false
    write_metadata          = false # We only want the clean transaction payload columns
    drop_unknown_properties = true  # Ignore properties not in BQ schema
  }

  depends_on = [
    google_bigquery_dataset_iam_member.pubsub_metadata,
    google_bigquery_dataset_iam_member.pubsub_data_editor
  ]
}