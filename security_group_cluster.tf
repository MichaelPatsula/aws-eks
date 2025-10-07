#########################################################################################
# Cluster Security Group
# Defaults follow https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html
# Associated on nodes & cluster
#########################################################################################

locals {
  cluster_security_group_rules = {
    ingress_nodes_443 = {
      description                = "Node groups to cluster API"
      protocol                   = "tcp"
      from_port                  = 443
      to_port                    = 443
      type                       = "ingress"
      source_node_security_group = true                          # node security groups
    }
  }
}

resource "aws_security_group" "cluster" {
  name_prefix = "${var.name}-nsg-cluster-"
  description = "Secures communication between the Kubernetes control plane and the worker nodes"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    { "Name" = "${var.name}-nsg-cluster" }
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "cluster" {
  for_each = { for k, v in merge(
    local.cluster_security_group_rules
  ) : k => v }

  # Required
  security_group_id = aws_security_group.cluster.id
  protocol          = each.value.protocol
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  type              = each.value.type

  # Optional
  description              = lookup(each.value, "description", null)
  cidr_blocks              = lookup(each.value, "cidr_blocks", null)
  ipv6_cidr_blocks         = lookup(each.value, "ipv6_cidr_blocks", null)
  prefix_list_ids          = lookup(each.value, "prefix_list_ids", null)
  self                     = lookup(each.value, "self", null)
  source_security_group_id = try(each.value.source_node_security_group, false) ? aws_security_group.node.id : lookup(each.value, "source_security_group_id", null)
}
