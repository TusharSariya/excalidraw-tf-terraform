output "vpc_id" {
  description = "VPC ID for workload subnets."
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "Allocated VPC IPv4 CIDR."
  value       = module.vpc.vpc_cidr_block
}

output "intra_subnets" {
  description = "Isolated subnet IDs for Lambda ENIs and interface endpoints."
  value       = module.vpc.intra_subnets
}

output "private_subnets" {
  description = "Private subnet IDs with default route through NAT (for workloads needing outbound internet)."
  value       = module.vpc.private_subnets
}

output "database_subnets" {
  description = "Database subnet IDs for RDS/Aurora subnet groups."
  value       = module.vpc.database_subnets
}

output "database_route_table_ids" {
  description = "Route tables associated with database subnets."
  value       = module.vpc.database_route_table_ids
}

output "public_subnets" {
  description = "Public subnet IDs for internet-facing load balancers and NAT gateways."
  value       = module.vpc.public_subnets
}

output "public_route_table_ids" {
  description = "Route tables associated with public subnets."
  value       = module.vpc.public_route_table_ids
}

output "default_route_table_id" {
  description = "Default route table for the VPC."
  value       = module.vpc.default_route_table_id
}

output "nat_gateway_public_ips" {
  description = "Elastic IP addresses associated with NAT gateways (one per NAT created)."
  value       = module.vpc.nat_public_ips
}

output "intra_route_table_ids" {
  description = "Route tables associated with intra subnets (S3 gateway endpoint)."
  value       = module.vpc.intra_route_table_ids
}

output "private_route_table_ids" {
  description = "Route tables associated with private subnets."
  value       = module.vpc.private_route_table_ids
}

output "route_table_ids" {
  description = "All VPC route tables created by the workload network module."
  value = distinct(concat(
    [module.vpc.default_route_table_id],
    module.vpc.public_route_table_ids,
    module.vpc.private_route_table_ids,
    module.vpc.intra_route_table_ids,
    module.vpc.database_route_table_ids,
  ))
}

output "route_table_id_map" {
  description = "All VPC route tables keyed by stable tier names for same-apply for_each use."
  value = {
    default  = module.vpc.default_route_table_id
    public   = module.vpc.public_route_table_ids[0]
    private  = module.vpc.private_route_table_ids[0]
    intra    = module.vpc.intra_route_table_ids[0]
    database = module.vpc.database_route_table_ids[0]
  }
}

output "interface_endpoint_security_group_id" {
  description = "Security group attached to interface VPC endpoints."
  value       = module.interface_endpoint_security_group.security_group_id
}

output "managed_service_endpoints" {
  description = "Created gateway + interface endpoints (module aws provider objects)."
  value       = module.managed_service_endpoints.endpoints
}

output "flow_log_id" {
  description = "VPC Flow Log resource ID."
  value       = module.vpc_flow_logs.flow_log_id
}

output "flow_log_group_name" {
  description = "CloudWatch Logs group receiving VPC Flow Logs."
  value       = module.vpc_flow_logs.log_group_name
}

output "flow_log_group_arn" {
  description = "CloudWatch Logs group ARN for VPC Flow Logs."
  value       = module.vpc_flow_logs.log_group_arn
}
