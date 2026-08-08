variable "project_id" {
  type        = string
  description = "GCP Project ID"
}

variable "region" {
  type        = string
  description = "GCP Region"
}

variable "environment" {
  type        = string
  description = "Deployment environment"
}

variable "vpc_name" {
  type        = string
  description = "Name of the VPC network"
}

variable "vpc_connector_id" {
  type        = string
  description = "ID of the Serverless VPC Access Connector"
}

variable "pubsub_topic_name" {
  type        = string
  description = "Name of the Pub/Sub topic to publish events"
}

variable "pubsub_topic_id" {
  type        = string
  description = "ID of the Pub/Sub topic to publish events"
}

variable "container_image" {
  type        = string
  description = "Container image URL to deploy in Cloud Run"
  default     = "gcr.io/cloudrun/hello"
}