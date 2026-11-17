output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block."
  value       = module.vpc.vpc_cidr_block
}

output "azs" {
  description = "Availability zones of the subnets."
  value       = module.vpc.azs
}

output "private_subnet_ids" {
  description = "Private subnet IDs (nodes, internal load balancers)."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs (NAT Gateway, internet-facing load balancers)."
  value       = module.vpc.public_subnets
}

output "nat_gateway_ids" {
  description = "NAT Gateway IDs."
  value       = module.vpc.natgw_ids
}
