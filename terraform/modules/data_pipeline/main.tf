data "google_project" "project" {}

# 1. Tópico de Pub/Sub para eventos de transacción
resource "google_pubsub_topic" "payment_events" {
  name = "tenpo-payment-events-${var.environment}"

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

# 2. Dataset de BigQuery para ingesta analítica
resource "google_bigquery_dataset" "analytics" {
  dataset_id                  = "tenpo_analytics_${var.environment}"
  friendly_name               = "Tenpo Analytics Dataset"
  description                 = "Dataset for payment transaction events ingestion"
  location                    = var.region
  default_table_expiration_ms = 31536000000 # 1 año en ms

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

# 3. Tabla de BigQuery para los datos estructurados de transacciones
resource "google_bigquery_table" "payment_transactions" {
  dataset_id          = google_bigquery_dataset.analytics.dataset_id
  table_id            = "payment_transactions"
  deletion_protection = false # Deshabilitado para facilitar pruebas y limpieza en el desafío

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

# 4. Permisos IAM para que la identidad de servicio de Pub/Sub escriba en BigQuery
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

# 5. Suscripción directa de Pub/Sub a BigQuery
resource "google_pubsub_subscription" "bq_ingest" {
  name  = "tenpo-payment-bq-sub-${var.environment}"
  topic = google_pubsub_topic.payment_events.name

  bigquery_config {
    table                   = "${var.project_id}:${google_bigquery_table.payment_transactions.dataset_id}.${google_bigquery_table.payment_transactions.table_id}"
    use_topic_schema        = false
    write_metadata          = false # Solo queremos las columnas del payload limpio de la transacción
    drop_unknown_properties = true  # Ignora propiedades que no estén en el esquema de BigQuery
  }

  depends_on = [
    google_bigquery_dataset_iam_member.pubsub_metadata,
    google_bigquery_dataset_iam_member.pubsub_data_editor
  ]
}