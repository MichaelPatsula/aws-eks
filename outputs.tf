output "cluster" {
    value = aws_eks_cluster.this
}

output "node_groups" {
    value = module.managed_node_group
}

output "iam_role" {
    value = {
        role       = aws_iam_role.this
        attachment = aws_iam_role_policy_attachment.this
        
        cluster_encryption_policy            = aws_iam_policy.cluster_encryption
        cluster_encryption_policy_attachment = aws_iam_role_policy_attachment.cluster_encryption
    }
}

output "access_entries" {
    value = aws_eks_access_entry.this
}

output "access_entry_associations" {
    value = aws_eks_access_policy_association.this
}

output "addons" {
    value = aws_eks_addon.this
}

output "encryption_key" {
    value = module.kms_encryption_key
}

