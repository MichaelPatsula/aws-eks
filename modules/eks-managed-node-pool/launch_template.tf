###################
# Launch template #
###################

resource "aws_launch_template" "this" {
  count = var.bootstrap_extra_args != null ? 1 : 0

  name        = "${var.cluster_name}-${var.name}-eks-node-group"
  description = "Launch template for ${var.name} node group within ${var.cluster_name} cluster"

  image_id  = null
  #vpc_security_group_ids = length(local.network_interfaces) > 0 ? [] : local.security_group_ids 
  update_default_version  = true

  dynamic "instance_market_options" {
    for_each = var.instance_market_options != null ? ["instance_market_options"] : []

    content {
      market_type = var.instance_market_options.market_type

      dynamic "spot_options" {
        for_each = instance_market_options.value.spot_options != null ? ["spot_options"] : []

        content {
          block_duration_minutes         = var.instance_market_options.spot_options.block_duration_minutes
          instance_interruption_behavior = var.instance_market_options.spot_options.instance_interruption_behavior
          max_price                      = var.instance_market_options.spot_options.max_price
          spot_instance_type             = var.instance_market_options.spot_options.spot_instance_type
          valid_until                    = var.instance_market_options.spot_options.valid_until
        }
      }
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_protocol_ipv6          = null
    http_put_response_hop_limit = 2
    http_tokens                 = "required"
    instance_metadata_tags      = null
  }

  maintenance_options {
    auto_recovery = "default" # "default" or "disabled"
  }

  monitoring {
    enabled = false
  }  

  user_data = var.bootstrap_extra_args != null ? base64encode(templatefile("${path.module}/../../templates/bottlerocket_user_data.tpl",{
      bootstrap_extra_args = var.bootstrap_extra_args
    })) : null

  dynamic "tag_specifications" {
    for_each = ["instance", "volume", "network-interface"]

    content {
      resource_type = tag_specifications.value
      tags          = merge(var.tags, { Name = var.name })
    }
  }

  tags = merge(
    var.tags
  )

  # Prevent premature access of policies by pods that
  # require permissions on create/destroy that depend on nodes
  depends_on = [
    aws_iam_role_policy_attachment.this
  ]

  # lifecycle {
  #   create_before_destroy = true
  # }
}



