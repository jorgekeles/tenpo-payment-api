# 1. VPC Network
resource "google_compute_network" "vpc" {
  name                    = "tenpo-vpc-${var.environment}"
  auto_create_subnetworks = false
}

# 2. Private Subnet for internal workloads
resource "google_compute_subnetwork" "private_subnet" {
  name                     = "tenpo-private-subnet-${var.environment}"
  ip_cidr_range            = "10.0.1.0/24"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true # Required for instances without public IPs to access Google APIs
}

# 3. Cloud Router (Prerequisite for Cloud NAT)
resource "google_compute_router" "router" {
  name    = "tenpo-router-${var.environment}"
  region  = var.region
  network = google_compute_network.vpc.id
}

# 4. Cloud NAT (Allows private resources to access the Internet)
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
# Allows Serverless workloads (like Cloud Run) to communicate privately with resources inside the VPC
resource "google_vpc_access_connector" "connector" {
  name          = "tenpo-vpc-conn-${var.environment}"
  region        = var.region
  ip_cidr_range = "10.8.0.0/28" # Must be a /28 block and not overlap with other subnets
  network       = google_compute_network.vpc.name
  min_instances = 2
  max_instances = 10
}