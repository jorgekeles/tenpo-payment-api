# 1. Red VPC
resource "google_compute_network" "vpc" {
  name                    = "tenpo-vpc-${var.environment}"
  auto_create_subnetworks = false
}

# 2. Subred privada para cargas de trabajo internas
resource "google_compute_subnetwork" "private_subnet" {
  name                     = "tenpo-private-subnet-${var.environment}"
  ip_cidr_range            = "10.0.1.0/24"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true # Requerido para acceder a las APIs de Google de forma privada
}

# 3. Cloud Router (Requisito para Cloud NAT)
resource "google_compute_router" "router" {
  name    = "tenpo-router-${var.environment}"
  region  = var.region
  network = google_compute_network.vpc.id
}

# 4. Cloud NAT (Permite a los recursos privados salir a Internet)
resource "google_compute_router_nat" "nat" {
  name                               = "tenpo-nat-${var.environment}"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# 5. Serverless VPC Access Connector
# Permite que los servicios Serverless (como Cloud Run) se comuniquen de forma privada dentro de la VPC
resource "google_vpc_access_connector" "connector" {
  name          = "tenpo-vpc-conn-${var.environment}"
  region        = var.region
  ip_cidr_range = "10.8.0.0/28" # Debe ser un bloque /28 y no solaparse con otras subredes
  network       = google_compute_network.vpc.name
  min_instances = 2
  max_instances = 10
}