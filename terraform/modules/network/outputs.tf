output "vpc_name" {
  value       = google_compute_network.vpc.name
  description = "The name of the VPC"
}

output "vpc_id" {
  value       = google_compute_network.vpc.id
  description = "The ID of the VPC"
}

output "private_subnet_name" {
  value       = google_compute_subnetwork.private_subnet.name
  description = "The name of the private subnet"
}

output "vpc_connector_id" {
  value       = google_vpc_access_connector.connector.id
  description = "The ID of the Serverless VPC Access Connector"
}