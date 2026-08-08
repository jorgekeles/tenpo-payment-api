terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# 1. Network Module (VPC, Subnets, NAT, VPC Connector)
module "network" {
  source      = "./modules/network"
  project_id  = var.project_id
  region      = var.region
  environment = var.environment
}

# 2. Data Pipeline Module (Pub/Sub topic, BigQuery and direct subscription)
module "data_pipeline" {
  source      = "./modules/data_pipeline"
  project_id  = var.project_id
  region      = var.region
  environment = var.environment
}

# 3. Service Module (Cloud Run, Service Account, Load Balancer, Cloud Armor)
module "service" {
  source            = "./modules/service"
  project_id        = var.project_id
  region            = var.region
  environment       = var.environment
  vpc_name          = module.network.vpc_name
  vpc_connector_id  = module.network.vpc_connector_id
  pubsub_topic_name = module.data_pipeline.pubsub_topic_name
  pubsub_topic_id   = module.data_pipeline.pubsub_topic_id
  container_image   = "gcr.io/cloudrun/hello" # Placeholder container image
}