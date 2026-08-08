# 1. Service Account for running the Cloud Run service (Minimum Privilege)
resource "google_service_account" "service_sa" {
  account_id   = "tenpo-payment-api-sa-${var.environment}"
  display_name = "Service Account for payment-api (${var.environment})"
}

# 2. IAM permissions for the Service Account
# Grant Logging Log Writer to allow structured logging
resource "google_project_iam_member" "logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.service_sa.email}"
}

# Grant Pub/Sub Publisher on the specific topic
resource "google_pubsub_topic_iam_member" "publisher" {
  topic  = var.pubsub_topic_id
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.service_sa.email}"
}

# 3. Cloud Run Service configured as private (Only accepting traffic from Load Balancer/VPC)
resource "google_cloud_run_v2_service" "payment_api" {
  name     = "tenpo-payment-api-${var.environment}"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER" # Only allow Load Balancer and internal VPC traffic

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
      egress    = "ALL_TRAFFIC" # Force all outbound traffic to pass through the VPC Connector -> NAT Gateway
    }
  }
}

# 4. Global Load Balancer Setup

# Reserve Static External IP
resource "google_compute_global_address" "lb_ip" {
  name = "tenpo-lb-static-ip-${var.environment}"
}

# Serverless Network Endpoint Group (NEG) pointing to the Cloud Run service
resource "google_compute_region_network_endpoint_group" "serverless_neg" {
  name                  = "tenpo-payment-api-neg-${var.environment}"
  network_endpoint_type = "SERVERLESS"
  region                = var.region

  cloud_run {
    service = google_cloud_run_v2_service.payment_api.name
  }
}

# Cloud Armor Security Policy (WAF)
resource "google_compute_security_policy" "cloud_armor" {
  name        = "tenpo-security-policy-${var.environment}"
  description = "Cloud Armor WAF policy for payment-api"

  # Default rule: Allow all
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

  # Security Rule: Block SQLi and XSS (OWASP Top 10)
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

# Backend Service for the Load Balancer
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

# URL Map routing requests to backend
resource "google_compute_url_map" "url_map" {
  name            = "tenpo-payment-api-urlmap-${var.environment}"
  default_service = google_compute_backend_service.backend.id
}

# --- HTTPS Setup ---

# Google-managed SSL Certificate (requires DNS validation for a real domain)
resource "google_compute_managed_ssl_certificate" "ssl_cert" {
  name = "tenpo-ssl-cert-${var.environment}"
  managed {
    domains = ["api-${var.environment}.tenpodevops.com"] # Placeholder domain name
  }
}

# HTTPS Proxy
resource "google_compute_target_https_proxy" "https_proxy" {
  name             = "tenpo-https-proxy-${var.environment}"
  url_map          = google_compute_url_map.url_map.id
  ssl_certificates = [google_compute_managed_ssl_certificate.ssl_cert.id]
}

# HTTPS Forwarding Rule (Port 443)
resource "google_compute_global_forwarding_rule" "https" {
  name                  = "tenpo-https-forwarding-rule-${var.environment}"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "443"
  target                = google_compute_target_https_proxy.https_proxy.id
  ip_address            = google_compute_global_address.lb_ip.id
}

# --- HTTP Setup (Optional/Backup) ---

# HTTP Proxy
resource "google_compute_target_http_proxy" "http_proxy" {
  name    = "tenpo-http-proxy-${var.environment}"
  url_map = google_compute_url_map.url_map.id
}

# HTTP Forwarding Rule (Port 80)
resource "google_compute_global_forwarding_rule" "http" {
  name                  = "tenpo-http-forwarding-rule-${var.environment}"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_target_http_proxy.http_proxy.id
  ip_address            = google_compute_global_address.lb_ip.id
}