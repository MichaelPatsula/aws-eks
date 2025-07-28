#############
# Node Pool #
#############

resource "aws_eks_node_group" "this" {
  node_group_name = var.name
  cluster_name    = var.cluster_name
  node_role_arn   = aws_iam_role.this.arn
  subnet_ids      = var.subnet_ids

  version              = var.node_group_version
  force_update_version = var.force_update_version

  # List of instance types associated with the EKS Node Group. Defaults to ["t3.medium"]
  # If you specify one instance type, all nodes in the group will use that type.
  # If you specify multiple instance types (especially for Spot capacity), the EKS node group can choose among them based on availability and pricing. (useful for spot in particular)
  instance_types = var.instance_types
  capacity_type  = var.capacity_type  # On-Demand or spot
  disk_size      = var.disk_size      # if using a custom LT, set disk size on custom LT or else it will error here

  # https://docs.aws.amazon.com/eks/latest/userguide/launch-templates.html#launch-template-custom-ami
  # The software image (OS + tools) used to boot the instance
  ami_type        = var.ami_type
  release_version = var.use_latest_ami_release_version ? local.latest_ami_release_version : var.ami_release_version

  scaling_config {
    min_size     = var.scaling.min_size
    max_size     = var.scaling.max_size
    desired_size = var.scaling.desired_size == null ? var.scaling.min_size : var.scaling.desired_size
  }

  // Allows you to customize the EC2 instance configuration beyond what the default node group options provide.
  // By default, EKS node groups only let you configure a few things like Instance type, disk size, AMI type
  // But launch templates let you:
  # ✅ Use a custom AMI (e.g., with pre-installed agents or security hardening)
  # ✅ Customize EBS volume settings (type, size, IOPS, etc.)
  # ✅ Enable instance metadata options (e.g., IMDSv2 required)
  # ✅ Add custom user data (e.g., shell scripts to run at boot)
  # ✅ Attach additional ENIs or IAM instance profiles 
  # ✅ Configure detailed monitoring, CPU options, etc.
  dynamic launch_template {
    for_each = var.bootstrap_extra_args != null ? ["launch"] : []

    content {
      id      = aws_launch_template.this[0].id
      version = try(aws_launch_template.this[0].default_version, "$Default")
    }
  }

  // Allows you to SSH into the EC2 instances (nodes) created by the node group. 
  // It configures how access to the worker nodes is set up using SSH keys and optionally restricts access by source IP ranges
  dynamic "remote_access" {
    for_each = var.ssh_access != null ? ["remote_access"] : []

    content {
      ec2_ssh_key               = var.ssh_access.ssh_key
      source_security_group_ids = var.ssh_access.security_group_ids
    }
  }

  // controls how updates (like AMI version upgrades & configuration changes (ex: labels or taint changes)) are rolled out to the node group
  dynamic "update_config" {
    for_each = var.update_config != null ? ["update_config"] : []

    content {
      max_unavailable_percentage = var.update_config.max_unavailable_percentage
      max_unavailable            = var.update_config.max_unavailable
    }
  }

  // When a node is not functioning correctly (e.g., it's unresponsive, stuck in NotReady state), EKS can automatically terminate and replace it with a new instance.
  node_repair_config {
    enabled = var.enable_node_repair
  }

  labels = var.labels
  dynamic "taint" {
    for_each = var.taints

    content {
      key    = taint.value.key
      value  = try(taint.value.value, null)
      effect = taint.value.effect
    }
  }  

  timeouts {
    create = try(var.timeouts.create, null)
    update = try(var.timeouts.update, null)
    delete = try(var.timeouts.delete, null)
  }

  lifecycle {
    #create_before_destroy = true
    ignore_changes = [
      scaling_config[0].desired_size,
    ]
  }

  tags = merge(
    var.tags,
    { Name = var.name }
  )
}

##############
## IAM Role ##
##############

resource "aws_iam_role" "this" {
  name        = "${var.name}-eks-node-group"
  path        = "/"
  description = "EKS managed node group IAM role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
        Sid    = "EKSNodeAssumeRole"
        Effect = "Allow",
        Principal = {
            Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }]
    })

  force_detach_policies = true

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = { for k, v in {
    AmazonEKSWorkerNodePolicy          = "arn:${data.aws_partition.this.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    AmazonEKS_CNI_Policy               = "arn:${data.aws_partition.this.partition}:iam::aws:policy/AmazonEKS_CNI_Policy",
    AmazonEC2ContainerRegistryReadOnly = "arn:${data.aws_partition.this.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  } : k => v }

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

##############################
# Latest AMI Release Version #
##############################

locals {
  # Just to ensure templating doesn't fail when values are not provided
  ssm_cluster_version = var.node_group_version != null ? var.node_group_version : ""
  ssm_ami_type        = try(var.ami_type != null, false) ? var.ami_type : ""

  # Map the AMI type to the respective SSM param path
  ssm_ami_type_to_ssm_param = {
    AL2_x86_64                 = "/aws/service/eks/optimized-ami/${local.ssm_cluster_version}/amazon-linux-2/recommended/release_version"
    AL2_x86_64_GPU             = "/aws/service/eks/optimized-ami/${local.ssm_cluster_version}/amazon-linux-2-gpu/recommended/release_version"
    AL2_ARM_64                 = "/aws/service/eks/optimized-ami/${local.ssm_cluster_version}/amazon-linux-2-arm64/recommended/release_version"
    CUSTOM                     = "NONE"
    BOTTLEROCKET_ARM_64        = "/aws/service/bottlerocket/aws-k8s-${local.ssm_cluster_version}/arm64/latest/image_version"
    BOTTLEROCKET_x86_64        = "/aws/service/bottlerocket/aws-k8s-${local.ssm_cluster_version}/x86_64/latest/image_version"
    BOTTLEROCKET_ARM_64_FIPS   = "/aws/service/bottlerocket/aws-k8s-${local.ssm_cluster_version}-fips/arm64/latest/image_version"
    BOTTLEROCKET_x86_64_FIPS   = "/aws/service/bottlerocket/aws-k8s-${local.ssm_cluster_version}-fips/x86_64/latest/image_version"
    BOTTLEROCKET_ARM_64_NVIDIA = "/aws/service/bottlerocket/aws-k8s-${local.ssm_cluster_version}-nvidia/arm64/latest/image_version"
    BOTTLEROCKET_x86_64_NVIDIA = "/aws/service/bottlerocket/aws-k8s-${local.ssm_cluster_version}-nvidia/x86_64/latest/image_version"
    WINDOWS_CORE_2019_x86_64   = "/aws/service/ami-windows-latest/Windows_Server-2019-English-Full-EKS_Optimized-${local.ssm_cluster_version}"
    WINDOWS_FULL_2019_x86_64   = "/aws/service/ami-windows-latest/Windows_Server-2019-English-Core-EKS_Optimized-${local.ssm_cluster_version}"
    WINDOWS_CORE_2022_x86_64   = "/aws/service/ami-windows-latest/Windows_Server-2022-English-Full-EKS_Optimized-${local.ssm_cluster_version}"
    WINDOWS_FULL_2022_x86_64   = "/aws/service/ami-windows-latest/Windows_Server-2022-English-Core-EKS_Optimized-${local.ssm_cluster_version}"
    AL2023_x86_64_STANDARD     = "/aws/service/eks/optimized-ami/${local.ssm_cluster_version}/amazon-linux-2023/x86_64/standard/recommended/release_version"
    AL2023_ARM_64_STANDARD     = "/aws/service/eks/optimized-ami/${local.ssm_cluster_version}/amazon-linux-2023/arm64/standard/recommended/release_version"
    AL2023_x86_64_NEURON       = "/aws/service/eks/optimized-ami/${local.ssm_cluster_version}/amazon-linux-2023/x86_64/neuron/recommended/release_version"
    AL2023_x86_64_NVIDIA       = "/aws/service/eks/optimized-ami/${local.ssm_cluster_version}/amazon-linux-2023/x86_64/nvidia/recommended/release_version"
  }

  # The Windows SSM params currently do not have a release version, so we have to get the full output JSON blob and parse out the release version
  windows_latest_ami_release_version = try(var.use_latest_ami_release_version, false) && startswith(local.ssm_ami_type, "WINDOWS") ? nonsensitive(jsondecode(data.aws_ssm_parameter.ami[0].value)["release_version"]) : null
  # Based on the steps above, try to get an AMI release version - if not, `null` is returned
  latest_ami_release_version = startswith(local.ssm_ami_type, "WINDOWS") ? local.windows_latest_ami_release_version : try(nonsensitive(data.aws_ssm_parameter.ami[0].value), null)
}
