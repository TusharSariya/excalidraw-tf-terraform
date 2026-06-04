# =============================================================================
# EKS-style stream processing layer and service-account roles
# =============================================================================

resource "aws_security_group" "eks_control_plane" {
  provider = aws.ingestion

  name        = "${local.environment}-extended-eks-control-plane"
  description = "EKS control plane access for extended stream processors"
  vpc_id      = module.ingestion_east_network.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidrs.east]
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.ingestion_vpc_cidrs.east]
  }

  tags = merge(local.extended_common_tags, { lane = "eks", role = "control-plane" })
}

resource "aws_security_group" "eks_nodes" {
  provider = aws.ingestion

  name        = "${local.environment}-extended-eks-nodes"
  description = "EKS worker node access to lake, streams, and regional writers"
  vpc_id      = module.ingestion_east_network.vpc_id

  ingress {
    from_port       = 10250
    to_port         = 10250
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_control_plane.id]
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = local.ingestion_all_peer_cidrs
  }

  tags = merge(local.extended_common_tags, { lane = "eks", role = "nodes" })
}

data "aws_iam_policy_document" "eks_cluster_assume" {
  provider = aws.ingestion

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "eks_node_assume" {
  provider = aws.ingestion

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "eks_fargate_assume" {
  provider = aws.ingestion

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks-fargate-pods.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  provider = aws.ingestion

  name               = "${local.environment}-extended-eks-cluster"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume.json

  tags = merge(local.extended_common_tags, { lane = "eks" })
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  provider = aws.ingestion

  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "eks_node" {
  provider = aws.ingestion

  name               = "${local.environment}-extended-eks-node"
  assume_role_policy = data.aws_iam_policy_document.eks_node_assume.json

  tags = merge(local.extended_common_tags, { lane = "eks" })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node" {
  provider = aws.ingestion

  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni" {
  provider = aws.ingestion

  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_registry" {
  provider = aws.ingestion

  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_cluster" "stream_processors" {
  provider = aws.ingestion

  name     = "${local.environment}-extended-stream-processors"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.32"

  vpc_config {
    subnet_ids              = module.ingestion_east_network.private_subnets
    security_group_ids      = [aws_security_group.eks_control_plane.id]
    endpoint_private_access = true
    endpoint_public_access  = false
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = merge(local.extended_common_tags, { lane = "eks", role = "cluster" })

  depends_on = [aws_iam_role_policy_attachment.eks_cluster]
}

resource "aws_eks_node_group" "stream_processors" {
  provider = aws.ingestion

  cluster_name    = aws_eks_cluster.stream_processors.name
  node_group_name = "${local.environment}-extended-stream-processors"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = module.ingestion_east_network.private_subnets

  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    workload = "stream-processing"
  }

  tags = merge(local.extended_common_tags, { lane = "eks", role = "node-group" })

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node,
    aws_iam_role_policy_attachment.eks_cni,
    aws_iam_role_policy_attachment.eks_registry,
  ]
}

resource "aws_iam_role" "eks_fargate" {
  provider = aws.ingestion

  name               = "${local.environment}-extended-eks-fargate"
  assume_role_policy = data.aws_iam_policy_document.eks_fargate_assume.json

  tags = merge(local.extended_common_tags, { lane = "eks" })
}

resource "aws_iam_role_policy_attachment" "eks_fargate" {
  provider = aws.ingestion

  role       = aws_iam_role.eks_fargate.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}

resource "aws_eks_fargate_profile" "stream_processors" {
  provider = aws.ingestion

  cluster_name           = aws_eks_cluster.stream_processors.name
  fargate_profile_name   = "${local.environment}-extended-stream-jobs"
  pod_execution_role_arn = aws_iam_role.eks_fargate.arn
  subnet_ids             = module.ingestion_east_network.private_subnets

  selector {
    namespace = "stream-processing"
    labels = {
      lane = "kinesis"
    }
  }

  tags = merge(local.extended_common_tags, { lane = "eks", role = "fargate" })

  depends_on = [aws_iam_role_policy_attachment.eks_fargate]
}

resource "aws_eks_addon" "core_dns" {
  provider = aws.ingestion

  cluster_name = aws_eks_cluster.stream_processors.name
  addon_name   = "coredns"

  tags = merge(local.extended_common_tags, { lane = "eks", addon = "coredns" })
}

resource "aws_eks_addon" "kube_proxy" {
  provider = aws.ingestion

  cluster_name = aws_eks_cluster.stream_processors.name
  addon_name   = "kube-proxy"

  tags = merge(local.extended_common_tags, { lane = "eks", addon = "kube-proxy" })
}

resource "aws_eks_addon" "vpc_cni" {
  provider = aws.ingestion

  cluster_name = aws_eks_cluster.stream_processors.name
  addon_name   = "vpc-cni"

  tags = merge(local.extended_common_tags, { lane = "eks", addon = "vpc-cni" })
}

resource "aws_eks_addon" "observability" {
  provider = aws.ingestion

  cluster_name = aws_eks_cluster.stream_processors.name
  addon_name   = "amazon-cloudwatch-observability"

  tags = merge(local.extended_common_tags, { lane = "eks", addon = "observability" })
}

data "aws_iam_policy_document" "eks_service_account_assume" {
  provider = aws.ingestion

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "oidc.eks.${local.regions.east}.amazonaws.com/id/localstack:sub"
      values = [
        "system:serviceaccount:stream-processing:s3-writer",
        "system:serviceaccount:stream-processing:kinesis-reader",
        "system:serviceaccount:stream-processing:sqs-dispatcher",
        "system:serviceaccount:stream-processing:dynamodb-writer",
        "system:serviceaccount:observability:cloudwatch-agent",
      ]
    }
  }
}

resource "aws_iam_openid_connect_provider" "eks" {
  provider = aws.ingestion

  url             = "https://oidc.eks.${local.regions.east}.amazonaws.com/id/localstack"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da0afd10df6"]

  tags = merge(local.extended_common_tags, { lane = "eks", role = "oidc" })
}

resource "aws_iam_role" "eks_service_accounts" {
  provider = aws.ingestion

  for_each = toset(["s3", "kinesis", "sqs", "dynamodb", "cloudwatch"])

  name               = "${local.environment}-extended-irsa-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.eks_service_account_assume.json

  tags = merge(local.extended_common_tags, { lane = "eks", irsa = each.key })
}

resource "aws_iam_role_policy" "eks_service_accounts" {
  provider = aws.ingestion

  for_each = aws_iam_role.eks_service_accounts

  name = "${local.environment}-extended-irsa-${each.key}"
  role = each.value.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = each.key == "cloudwatch" ? ["cloudwatch:PutMetricData", "logs:PutLogEvents"] : ["${each.key}:*"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_security_group" "cluster_to_lake" {
  provider = aws.ingestion

  name        = "${local.environment}-extended-cluster-to-lake"
  description = "Render lane from EKS stream processors to S3 lake"
  vpc_id      = module.ingestion_east_network.vpc_id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.extended_common_tags, { lane = "eks", edge = "lake" })
}

resource "aws_security_group" "cluster_to_kafka" {
  provider = aws.ingestion

  name        = "${local.environment}-extended-cluster-to-kafka"
  description = "Render lane from EKS stream processors to MSK"
  vpc_id      = module.ingestion_east_network.vpc_id

  egress {
    from_port   = 9098
    to_port     = 9098
    protocol    = "tcp"
    cidr_blocks = [local.ingestion_vpc_cidrs.east]
  }

  tags = merge(local.extended_common_tags, { lane = "eks", edge = "kafka" })
}

resource "aws_cloudwatch_log_group" "kafka_backbone" {
  provider = aws.ingestion

  name              = "/aws/msk/${local.environment}-extended-events"
  retention_in_days = 30
  tags              = merge(local.extended_common_tags, { lane = "kafka" })
}

resource "aws_cloudwatch_log_group" "redis_cache" {
  provider = aws.ingestion

  name              = "/aws/elasticache/${local.environment}-extended-redis"
  retention_in_days = 30
  tags              = merge(local.extended_common_tags, { lane = "redis" })
}

resource "aws_security_group" "eks_to_regional_writers" {
  provider = aws.ingestion

  name        = "${local.environment}-extended-cluster-to-regional-writers"
  description = "Render lane from EKS stream processors to regional writer queues"
  vpc_id      = module.ingestion_east_network.vpc_id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = local.ingestion_all_peer_cidrs
  }

  tags = merge(local.extended_common_tags, { lane = "eks", edge = "regional-writers" })
}
