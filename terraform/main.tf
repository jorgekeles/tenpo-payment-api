# 1. Módulo de Red (VPC, subredes, NAT, VPC Connector)
module "network" {
  source      = "./modules/network"
  project_id  = var.project_id
  region      = var.region
  environment = var.environment
}

# 2. Módulo del Pipeline de Datos (Tópico de Pub/Sub, BigQuery y suscripción directa)
module "data_pipeline" {
  source      = "./modules/data_pipeline"
  project_id  = var.project_id
  region      = var.region
  environment = var.environment
}

# 3. Módulo del Servicio (Cloud Run, Service Account, Load Balancer, Cloud Armor)
module "service" {
  source            = "./modules/service"
  project_id        = var.project_id
  region            = var.region
  environment       = var.environment
  vpc_name          = module.network.vpc_name
  vpc_connector_id  = module.network.vpc_connector_id
  pubsub_topic_name = module.data_pipeline.pubsub_topic_name
  pubsub_topic_id   = module.data_pipeline.pubsub_topic_id
  container_image   = "gcr.io/cloudrun/hello" # Imagen temporal
}