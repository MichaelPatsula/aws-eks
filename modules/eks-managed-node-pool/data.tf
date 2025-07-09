data "aws_partition" "this" {}

data "aws_ssm_parameter" "ami" {
  count = try(var.use_latest_ami_release_version, false) ? 1 : 0

  name = local.ssm_ami_type_to_ssm_param[var.ami_type]
}