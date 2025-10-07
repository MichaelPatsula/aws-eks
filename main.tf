# eks:DescribeCluster for kubeconfig
resource "aws_eks_cluster" "this" {
  name                          = "${var.name}-eks"
  role_arn                      = aws_iam_role.this.arn
  version                       = var.cluster_version
  force_update_version          = var.force_update_version  
  enabled_cluster_log_types     = var.enabled_cluster_log_types

  # indicate whether Install default unmanaged add-ons, such as aws-cni, kube-proxy, and CoreDNS during cluster creation. 
  # If false, you must manually install desired add-ons through aws_eks_addon.
  bootstrap_self_managed_addons = var.bootstrap_self_managed_addons


  access_config {
    # determines how IAM identities are granted access to the Kubernetes API server
    # config_map (legacy) or api
    authentication_mode = "API"

    # See access entries below - this is a one time operation from the EKS API.
    # Instead, we are hardcoding this to false and if users wish to achieve this
    # same functionality, we will do that through an access entry which can be
    # enabled or disabled at any time of their choosing using the variable
    # var.enable_cluster_creator_admin_permissions
    bootstrap_cluster_creator_admin_permissions = false
  }

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = var.security_groups.use_custom_security_group ? [aws_security_group.cluster.id] : null
    
    # Whether the Amazon EKS private API server endpoint is enabled.
    endpoint_private_access = var.api_server.endpoint_private_access
    # Whether the Amazon EKS public API server endpoint is enabled
    endpoint_public_access  = var.api_server.endpoint_public_access
    public_access_cidrs     = var.api_server.public_access_cidrs
  }

  dynamic "kubernetes_network_config" {
    for_each = var.kubernetes_network_config != null ? ["kubernetes_network_config"] : []   

    content {
      ip_family         = var.kubernetes_network_config.ip_family
      service_ipv4_cidr = var.kubernetes_network_config.service_ipv4_cidr
      service_ipv6_cidr = var.kubernetes_network_config.service_ipv6_cidr
    }
  }

  dynamic "encryption_config" {
    for_each = var.encrypt_kubernetes_secrets ? ["encryption_config"] : []    

    content {
      provider {
        key_arn = module.kms_encryption_key[0].key_arn
      }
      resources = ["secrets"]
    }
  }

  upgrade_policy {
    support_type = var.support_type
  }

  tags = merge(
    { terraform-aws-modules = "eks" },
    var.tags
  )

  timeouts {
    create = try(var.timeouts.create, null)
    update = try(var.timeouts.update, null)
    delete = try(var.timeouts.delete, null)
  }

  depends_on = [
    aws_iam_role_policy_attachment.this,
  ]

  lifecycle {
    ignore_changes = [
      access_config[0].bootstrap_cluster_creator_admin_permissions
    ]
  }
}

##############
## IAM Role ##
##############

## Standard ##

resource "aws_iam_role" "this" {
  name = "eks-cluster-role"
  path        = "/"
  description = "EKS managed node group IAM role"  

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "EKSClusterAssumeRole"
        Effect = "Allow"
        Action = [
          "sts:AssumeRole",
          "sts:TagSession",
        ]
        Principal = {
          Service = ["eks.amazonaws.com"],
        }
      }
    ]
  })

  force_detach_policies = true
  tags                  = var.tags  
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = { for k, v in {
    AmazonEKSClusterPolicy = "arn:${data.aws_partition.this.partition}:iam::aws:policy/AmazonEKSClusterPolicy",
  } : k => v }

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

## Cluster Encryption

resource "aws_iam_role_policy_attachment" "cluster_encryption" {
  count = var.encrypt_kubernetes_secrets ? 1 : 0

  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.cluster_encryption[0].arn
}

resource "aws_iam_policy" "cluster_encryption" {
  count = var.encrypt_kubernetes_secrets ? 1 : 0

  name        = "${var.name}-cluster-encryption-policy"
  description = "EKS policy for cluster encryption."
  path        = "/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ListGrants",
          "kms:DescribeKey",
        ]
        Effect   = "Allow"
        Resource = module.kms_encryption_key[0].key_arn
      },
    ]
  })

  tags = var.tags
}

####################
## Access Entries ##
####################

locals {
  partition = try(data.aws_partition.this.partition, "")

  bootstrap_cluster_creator_admin_permissions = {
    cluster_creator = {
      principal_arn = try(data.aws_iam_session_context.this.issuer_arn, "")
      type          = "STANDARD"

      policy_associations = {
        admin = {
          policy_arn = "arn:${local.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  # Merge the bootstrap behavior with the entries that users provide
  merged_access_entries = merge(
    { for k, v in local.bootstrap_cluster_creator_admin_permissions : k => v },
    var.access_entries,
  )

  # Flatten out entries and policy associations so users can specify the policy
  # associations within a single entry
  flattened_access_entries = flatten([
    for entry_key, entry_val in local.merged_access_entries : [
      for pol_key, pol_val in lookup(entry_val, "policy_associations", {}) :
      merge(
        {
          principal_arn = entry_val.principal_arn
          entry_key     = entry_key
          pol_key       = pol_key
        },
        { for k, v in {
          association_policy_arn              = pol_val.policy_arn
          association_access_scope_type       = pol_val.access_scope.type
          association_access_scope_namespaces = lookup(pol_val.access_scope, "namespaces", [])
        } : k => v if !contains(["EC2_LINUX", "EC2_WINDOWS", "FARGATE_LINUX", "HYBRID_LINUX"], lookup(entry_val, "type", "STANDARD")) },
      )
    ]
  ])
}

# defines who is allowed to access the EKS cluster.
resource "aws_eks_access_entry" "this" {
  for_each = { for k, v in local.merged_access_entries : k => v }

  cluster_name      = aws_eks_cluster.this.id
  principal_arn     = each.value.principal_arn

  kubernetes_groups = try(each.value.kubernetes_groups, null)
  user_name         = try(each.value.user_name, null)
  type              = each.value.type        # STANDARD, EC2_LINUX, EC2_WINDOWS, FARGATE_LINUX   

  tags = var.tags
}

# defines what permissions the registered identity has inside the Kubernetes cluster
resource "aws_eks_access_policy_association" "this" {
  for_each = { for k, v in local.flattened_access_entries : "${v.entry_key}_${v.pol_key}" => v }

  cluster_name = aws_eks_cluster.this.id
  principal_arn = each.value.principal_arn
  policy_arn    = each.value.association_policy_arn             # ex: AmazonEKSAdminPolicy ref: https://docs.aws.amazon.com/eks/latest/userguide/access-policy-permissions.html
  
  access_scope {
    type       = each.value.association_access_scope_type        # namespace or cluster
    namespaces = each.value.association_access_scope_namespaces
  }

  depends_on = [
    aws_eks_access_entry.this,
  ]
}

################
## EKS Addons ##
################

locals {
  # TODO - Set to `NONE` on next breaking change when default addons are disabled
  resolve_conflicts_on_create_default = coalesce(var.bootstrap_self_managed_addons, true) ? "OVERWRITE" : "NONE"
}

resource "aws_eks_addon" "this" {
  for_each = { for k, v in var.cluster_addons : k => v if !try(v.before_compute, false) }

  cluster_name = aws_eks_cluster.this.id
  addon_name   = each.key

  addon_version        = coalesce(try(each.value.addon_version, null), data.aws_eks_addon_version.this[each.key].version)
  configuration_values = each.value.configuration_values

  dynamic "pod_identity_association" {
    for_each = each.value.pod_identity_association != null ? ["pod_identity_association"] : []

    content {
      role_arn        = pod_identity_association.value.role_arn
      service_account = pod_identity_association.value.service_account
    }
  }

  preserve = each.value.preserve

  # TODO - Set to `NONE` on next breaking change when default addons are disabled
  resolve_conflicts_on_create = try(each.value.resolve_conflicts_on_create, local.resolve_conflicts_on_create_default)
  resolve_conflicts_on_update = try(each.value.resolve_conflicts_on_update, "OVERWRITE")
  service_account_role_arn    = each.value.service_account_role_arn

  timeouts {
    create = try(var.timeouts.create, null)
    update = try(var.timeouts.update, null)
    delete = try(var.timeouts.delete, null)
  }

  depends_on = [
    module.managed_node_group,
  ]

  tags = merge(var.tags, try(each.value.tags, {}))
}

# resource "aws_eks_addon" "before_compute" {
#   for_each = { for k, v in var.cluster_addons : k => v if try(v.before_compute, false) }

#   cluster_name = aws_eks_cluster.this.id
#   addon_name   = each.key

#   addon_version        = coalesce(try(each.value.addon_version, null), data.aws_eks_addon_version.this[each.key].version)
#   configuration_values = each.value.configuration_values

#   dynamic "pod_identity_association" {
#     for_each = each.value.pod_identity_association != null ? ["pod_identity_association"] : []

#     content {
#       role_arn        = pod_identity_association.value.role_arn
#       service_account = pod_identity_association.value.service_account
#     }
#   }

#   preserve = each.value.preserve

#   # TODO - Set to `NONE` on next breaking change when default addons are disabled
#   resolve_conflicts_on_create = try(each.value.resolve_conflicts_on_create, local.resolve_conflicts_on_create_default)
#   resolve_conflicts_on_update = try(each.value.resolve_conflicts_on_update, "OVERWRITE")
#   service_account_role_arn    = each.value.service_account_role_arn

#   timeouts {
#     create = try(var.timeouts.create, null)
#     update = try(var.timeouts.update, null)
#     delete = try(var.timeouts.delete, null)
#   }

#   tags = merge(var.tags, try(each.value.tags, {}))
# }

########################
## EKS Encryption Key ##
########################

module "kms_encryption_key" {
  count = var.encrypt_kubernetes_secrets ? 1 : 0

  source  = "terraform-aws-modules/kms/aws"
  version = "2.1.0"

  description             = "KMS key for EKS encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 10
  aliases                 = ["alias/my-eks-key"]

	# IAM principals that can manage (but not use) the key
  key_administrators = [try(data.aws_iam_session_context.this.issuer_arn, "")]
  # IAM principals that can use (but not manage) the key
  key_users = [aws_iam_role.this.arn]
}

#################
## Node Groups ##
#################

module "managed_node_group" {
  for_each = var.node_groups
  source = "./modules/eks-managed-node-pool"

  name         = each.key
  cluster_name = aws_eks_cluster.this.id

  instance_types     = each.value.instance_types
  capacity_type      = each.value.capacity_type
  disk_size          = each.value.disk_size
  subnet_ids         = each.value.subnet_ids
  security_group_ids = [aws_security_group.node.id]

  ami_type                       = each.value.ami_type
  ami_release_version            = each.value.ami_release_version
  use_latest_ami_release_version = each.value.use_latest_ami_release_version

  node_group_version   = each.value.version
  force_update_version = each.value.force_update_version

  scaling            = each.value.scaling
  update_config      = each.value.update_config
  ssh_access         = each.value.ssh_access
  enable_node_repair = each.value.enable_node_repair

  instance_market_options = each.value.instance_market_options
  bootstrap_extra_args    = each.value.bootstrap_extra_args

  labels = each.value.labels
  taints = each.value.taints
}
