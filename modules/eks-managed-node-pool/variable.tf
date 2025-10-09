variable "name" {
    description = "The name of the node group."
    type        = string
}

variable "cluster_name" {
    description = "The name of the cluster the node group will be in."
    type        = string
}

variable "subnet_ids" {
    description = "Identifiers of EC2 Subnets to associate with the EKS Node Group."
    type        = list(string)
}

variable "vpc_id" {
    description = "The VPC used for the security group"
    type        = string
}

variable "custom_security_group_ids" {
    description = "The security groups to configure on the Launch Template, which will be used for the managed node group."
    type        = map(object({
        type                     = string
        description              = string
        protocol                 = string
        from_port                = number
        to_port                  = number
        source_security_group_id = string
    }))
    default = {}
}

variable "security_group_ids" {
    description = "The security groups to configure on the Launch Template, which will be used for the managed node group."
    type        = list(string)
    default     = []
}

variable "node_group_version" {
    description = "Kubernetes version. Defaults to EKS Cluster Kubernetes version"
    type        = number
    default     = null
}

variable "force_update_version" {
    description = "Force version update if existing pods are unable to be drained due to a pod disruption budget issue."
    type        = bool
    default     = false
}

###############
##  VM Type  ##    
###############

variable "instance_types" {
    description = "List of instance types associated with the EKS Node Group. Defaults to ['t3.medium']"
    type        = list(string)
    default     = null
}

variable "capacity_type" {
    description = "Type of capacity associated with the EKS Node Group. Valid values: ON_DEMAND, SPOT."
    type        = string
    default     = "ON_DEMAND"
}

variable "disk_size" {
    description = "Disk size in GiB for worker nodes. Defaults to 50 for Windows, 20 all other node groups."
    type        = string
    default     = null
}

## AMI (Amazon Machine Image) ##

variable "ami_type" {
    description = "Type of Amazon Machine Image (AMI) associated with the EKS Node Group"
    type        = string
    default     = null
}

variable "ami_release_version" {
    description = "AMI version of the EKS Node Group. Defaults to latest version for Kubernetes version."
    type        = string
    default     = null
}

variable "use_latest_ami_release_version" {
    description = "Determines whether to use the latest AMI release version for the given `ami_type` (except for `CUSTOM`)."
    type        = bool
    default     = false
}

# variable "ami" {
#     description = "Type of Amazon Machine Image (AMI) associated with the EKS Node Group & the release version of it."
#     type = object({
#         type                       = string
#         release_version            = optional(string)
#         use_latest_release_version = bool
#     })
# }

variable "instance_market_options" {
    description = "The market (purchasing) option for the instance"
    type = object({
            martket_type = optional(string, "spot")
            spot_options = object({
                block_duration_minutes         = string
                instance_interruption_behavior = optional(string)
                max_price                      = string
                spot_instance_type             = string
                valid_until                    = string
            })
        })
    default = null    
}

variable "bootstrap_extra_args" {
    description = ""
    type        = string
}

###############
##  VM Type  ##    
###############

variable "scaling" {
    description = "Scaling configuration for the node pool."
    type = object({
        min_size     = number
        max_size     = number
        desired_size = optional(number)
    })
}

variable "update_config" {
    description = "Desired max percentage/number of unavailable worker nodes during node group update"
    type = object({
        max_unavailable_percentage = optional(number)
        max_unavailable            = optional(number)
    })
}

variable "enable_node_repair" {
    description = "Specifies whether to enable node auto repair for the node group."
    type        = bool
    default     = false
}

variable "ssh_access" {
    description = "EC2 Key Pair name that provides access for remote communication with the worker nodes in the EKS Node Group."
    type = object({
        ssh_key            = optional(string)
        security_group_ids = optional(list(string))
    })
    default = null
}

variable "iam_role_additional_policies" {
    description = "Add additional policies to the role attached to the nodes"
    type        = map(string)
    default     = {}
}

#############
##  Other  ##    
#############

variable "labels" {
    description = "Key-value map of Kubernetes labels."
    type        = map(string)
    default = {}
}

variable "taints" {
    description = "The Kubernetes taints to be applied to the nodes in the node group. Maximum of 50 taints per node group."
    type        = list(object({
        key    = string
        value  = optional(string)
        effect = string
    }))
    default = []
}

variable "timeouts" {
    type = object({
        create = optional(string, "15m")
        update = optional(string, "15m")
        delete = optional(string, "15m")
    })
    default = null
}

variable "tags" {
    type    = map(string)
    default = {}
}