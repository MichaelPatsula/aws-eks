output "node_group" {
    value = aws_eks_node_group.this
}

output "iam_role" {
    value = aws_iam_role.this
}

output "iam_role_policy_attachment" {
    value = aws_iam_role_policy_attachment.this
}