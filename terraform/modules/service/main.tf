# 1. Service Account para ejecutar el servicio de Cloud Run (Mínimo Privilegio)
resource "google_service_account" "service_sa" {
  account_id   = "tenpo-payment-api-sa-${var.environment}"
  display_name = "Service Account for payment-api (${var.environment})"
}

# 2. Permisos IAM para la Service Account
# Permite escribir logs estructurados en Cloud Logging
resource "google_project_iam_member" "logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.service_sa.email}"
}

# Permite publicar mensajes en el tópico específico de Pub/Sub
resource "google_pubsub_topic_iam_member" "publisher" {
  topic  = var.pubsub_topic_id
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.service_sa.email}"
}

# 3. Servicio de Cloud Run configurado como privado (Solo acepta tráfico del VPC/Load Balancer)
resource "google_cloud_run_v2_service" "payment_api" {
  name     = "tenpo-payment-api-${var.environment}"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER" # Solo permite tráfico del Load Balancer y de la VPC

  template {
    service_account = google_service_account.service_sa.email

    containers {
      image = var.container_image

      ports {
        container_port = 8080
      }

      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }
      env {
        name  = "PUBSUB_TOPIC"
        value = var.pubsub_topic_name
      }
      env {
        name  = "GCP_PROJECT"
        value = var.project_id
      }
    }

    vpc_access {
      connector = var.vpc_connector_id
      egress    = "ALL_TRAFFIC" # Fuerza a que todo el tráfico de salida pase por el VPC Access Connector -> NAT Gateway
    }
  }
}

# 4. Configuración del Load Balancer Global

# Reserva una dirección IP estática global
resource "google_compute_global_address" "lb_ip" {
  name = "tenpo-lb-static-ip-${var.environment}"
}

# Network Endpoint Group (NEG) Serverless apuntando al servicio de Cloud Run
resource "google_compute_region_network_endpoint_group" "serverless_neg" {
  name                  = "tenpo-payment-api-neg-${var.environment}"
  network_endpoint_type = "SERVERLESS"
  region                = var.region

  cloud_run {
    service = google_cloud_run_v2_service.payment_api.name
  }
}

# Política de seguridad de Cloud Armor (WAF)
resource "google_compute_security_policy" "cloud_armor" {
  name        = "tenpo-security-policy-${var.environment}"
  description = "Cloud Armor WAF policy for payment-api"

  # Regla por defecto: Permitir todo
  rule {
    action   = "allow"
    priority = "2147483647"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "default rule"
  }

  # Regla de seguridad: Bloquear SQLi y XSS (OWASP Top 10)
  rule {
    action   = "deny(403)"
    priority = "1000"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('sqli-v33-stable') || evaluatePreconfiguredExpr('xss-v33-stable')"
      }
    }
    description = "WAF: block SQLi and XSS"
  }
}

# Servicio de Backend para el Load Balancer
resource "google_compute_backend_service" "backend" {
  name                  = "tenpo-payment-api-backend-${var.environment}"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  security_policy       = google_compute_security_policy.cloud_armor.id

  backend {
    group = google_compute_region_network_endpoint_group.serverless_neg.id
  }
}

# URL Map para enrutar las peticiones al Backend
resource "google_compute_url_map" "url_map" {
  name            = "tenpo-payment-api-urlmap-${var.environment}"
  default_service = google_compute_backend_service.backend.id
}

# --- Configuración HTTPS ---

# Certificado SSL gestionado por Google (requiere validación DNS para dominios reales)
resource "google_compute_managed_ssl_certificate" "ssl_cert" {
  name = "tenpo-ssl-cert-${var.environment}"
  managed {
    domains = ["api-${var.environment}.tenpodevops.com"] # Nombre de dominio temporal (placeholder)
  }
}

# Proxy HTTPS
resource "google_compute_target_https_proxy" "https_proxy" {
  name             = "tenpo-https-proxy-${var.environment}"
  url_map          = google_compute_url_map.url_map.id
  ssl_certificates = [google_compute_managed_ssl_certificate.ssl_cert.id]
}

# Regla de reenvío HTTPS (Puerto 443)
resource "google_compute_global_forwarding_rule" "https" {
  name                  = "tenpo-https-forwarding-rule-${var.environment}"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "443"
  target                = google_compute_target_https_proxy.https_proxy.id
  ip_address            = google_compute_global_address.lb_ip.id
}

# --- Configuración HTTP (Opcional/Respaldo) ---

# Proxy HTTP
resource "google_compute_target_http_proxy" "http_proxy" {
  name    = "tenpo-http-proxy-${var.environment}"
  url_map = google_compute_url_map.url_map.id
}

# Regla de reenvío HTTP (Puerto 80)
resource "google_compute_global_forwarding_rule" "http" {
  name                  = "tenpo-http-forwarding-rule-${var.environment}"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_target_http_proxy.http_proxy.id
  ip_address            = google_compute_global_address.lb_ip.id
}

# Repositorio de Artifact Registry para almacenar las imágenes de Docker de la API
resource "google_artifact_registry_repository" "tenpo_repo" {
  location      = var.region
  repository_id = "tenpo-repo"
  description   = "Repositorio Docker para almacenar las imagenes de payment-api"
  format        = "DOCKER"

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}