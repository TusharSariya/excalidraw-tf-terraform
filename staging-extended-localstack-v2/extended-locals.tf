locals {
  lake_bucket_families = toset([
    "raw",
    "curated",
    "archive",
    "quarantine",
    "model-artifact",
    "spark-script",
    "kafka-connect",
  ])

  security_bucket_families = toset([
    "audit",
    "access-log",
  ])

  replica_regions = {
    west   = local.regions.west
    west_1 = local.regions.west_1
    east_2 = local.regions.east_2
  }

  regional_writer_targets = {
    east = {
      provider_key = "east"
      region       = local.regions.east
      vpc_id       = module.ingestion_east_network.vpc_id
      subnet_ids   = module.ingestion_east_network.database_subnets
      vpc_cidr     = local.ingestion_vpc_cidrs.east
    }
    west = {
      provider_key = "west"
      region       = local.regions.west
      vpc_id       = module.ingestion_west_network.vpc_id
      subnet_ids   = module.ingestion_west_network.database_subnets
      vpc_cidr     = local.ingestion_vpc_cidrs.west
    }
    west_1 = {
      provider_key = "west_1"
      region       = local.regions.west_1
      vpc_id       = module.ingestion_west_1_network.vpc_id
      subnet_ids   = module.ingestion_west_1_network.database_subnets
      vpc_cidr     = local.ingestion_vpc_cidrs.west_1
    }
    east_2 = {
      provider_key = "east_2"
      region       = local.regions.east_2
      vpc_id       = module.ingestion_east_2_network.vpc_id
      subnet_ids   = module.ingestion_east_2_network.database_subnets
      vpc_cidr     = local.ingestion_vpc_cidrs.east_2
    }
  }

  extended_common_tags = merge(local.tags, {
    platform = "render-first-production-fiction"
    tier     = "extended"
  })
}
