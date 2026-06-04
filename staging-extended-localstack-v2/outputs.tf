# Key outputs for parity checking and pipeline consumption

output "east_vpc_id" {
  value = module.east_network.vpc_id
}

output "west_vpc_id" {
  value = module.west_network.vpc_id
}

output "west_1_vpc_id" {
  value = module.west_1_network.vpc_id
}

output "east_2_vpc_id" {
  value = module.east_2_network.vpc_id
}

output "east_execute_api_vpce_id" {
  value = aws_vpc_endpoint.east_execute_api.id
}

output "west_execute_api_vpce_id" {
  value = aws_vpc_endpoint.west_execute_api.id
}

output "west_1_execute_api_vpce_id" {
  value = aws_vpc_endpoint.west_1_execute_api.id
}

output "east_2_execute_api_vpce_id" {
  value = aws_vpc_endpoint.east_2_execute_api.id
}

output "ingress_queue_url" {
  value = module.ingress_queue.queue_url
}

output "egress_queue_url" {
  value = module.egress_queue.queue_url
}

output "consumer_lambda_arn" {
  value = module.consumer_lambda.lambda_function_arn
}

output "alb_dns_name" {
  value = aws_lb.ecs.dns_name
}

output "api_ids" {
  value = {
    api1  = module.api1.api_id
    api2  = module.api2.api_id
    api3  = module.api3.api_id
    api4  = module.api4.api_id
    api5  = module.api5.api_id
    api6  = module.api6.api_id
    api7  = module.api7.api_id
    api8  = module.api8.api_id
    api9  = module.api9.api_id
    api10 = module.api10.api_id
    api11 = module.api11.api_id
    api12 = module.api12.api_id
    api14 = module.api14.api_id
    api15 = module.api15.api_id
    api16 = module.api16.api_id
  }
}

output "extended_lake_buckets" {
  value = {
    for name, bucket in aws_s3_bucket.lake : name => bucket.bucket
  }
}

output "extended_kinesis_streams" {
  value = {
    provisioned = aws_kinesis_stream.provisioned.name
    burst       = aws_kinesis_stream.burst_on_demand.name
  }
}

output "extended_eks_cluster_name" {
  value = aws_eks_cluster.stream_processors.name
}

output "extended_state_machine_arn" {
  value = aws_sfn_state_machine.lake_curation.arn
}
