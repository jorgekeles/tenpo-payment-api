variable "project_id" {
  type        = string
  description = "The GCP Project ID"
  default     = "tenpo-payment-challenge"
}

variable "region" {
  type        = string
  description = "GCP Region for resources"
  default     = "us-central1"
}

variable "environment" {
  type        = string
  description = "Deployment environment (e.g. dev, prod)"
  default     = "dev"
}