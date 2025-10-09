resource "aws_security_group" "custom" {
  name_prefix = "${var.name}-nsg-node-custom"
  description = "${var.name} custom node group security group"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      "Name"                                      = "${var.name}-nsg-node-custom"
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "custom" {
  for_each = var.custom_security_group_ids

  # Required
  security_group_id = aws_security_group.custom.id
  protocol          = each.value.protocol
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  type              = each.value.type

  # Optional
  description              = lookup(each.value, "description", null)
  cidr_blocks              = lookup(each.value, "cidr_blocks", null)
  ipv6_cidr_blocks         = lookup(each.value, "ipv6_cidr_blocks", null)
  prefix_list_ids          = lookup(each.value, "prefix_list_ids", [])
  self                     = lookup(each.value, "self", null)
  source_security_group_id = lookup(each.value, "source_security_group_id", null)
}
