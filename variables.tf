variable "name" {
    description = "The name of the EKS cluster"
    type        = string
}

variable "cluster_version" {
    description = "The Kubernetes version of the control plane."
    type        = string
}

variable "force_update_version" {
    description = "Force version update by overriding upgrade-blocking readiness checks when updating a cluster."
    type        = bool
    default     = false
}

variable "enabled_cluster_log_types" {
    description = "List of the desired control plane logging to enable. API server (api), Audit (audit), Authenticator (authenticator), Controller manager (controllerManager) & Scheduler (scheduler)."
    type        = list(string)
    default     = []
}

################
## Networking ##
################

variable "subnet_ids" {
    description = "List of subnet IDs. Must be in at least two different availability zones. Amazon EKS creates cross-account elastic network interfaces in these subnets to allow communication between your worker nodes and the Kubernetes control plane."
    type        = list(string)
}

variable "security_group_ids" {
    description = "List of security group IDs for the cross-account elastic network interfaces that Amazon EKS creates to use to allow communication between your worker nodes and the Kubernetes control plane."
    type        = list(string)
    default     = null
}

variable "api_server" {
    description = "Configures Amazon EKS API server"
    type = object({
        endpoint_private_access = optional(bool, true)
        endpoint_public_access  = optional(bool, false)
        public_access_cidrs     = optional(list(string))
    })
    default = {
        endpoint_private_access = true
        endpoint_public_access  = false
    }
}

variable "kubernetes_network_config" {
    description = "Configuration block with kubernetes network configuration for the cluster."
    type = object({
        ip_family         = optional(string, "ipv4")
        service_ipv4_cidr = optional(string)
        service_ipv6_cidr = optional(string)    
    })
    default = {
        ip_family         = "ipv4"
        service_ipv4_cidr = null
        service_ipv6_cidr = null
    }
}

##########
## RBAC ##
##########

variable "encrypt_kubernetes_secrets" {
    description = ""
    type        = bool
    default     = true
}

variable "access_entries" {
    description = "List of the desired control plane logging to enable. API server (api), Audit (audit), Authenticator (authenticator), Controller manager (controllerManager) & Scheduler (scheduler)."
    type        = map(object({
        principal_arn = string
        type          = optional(string, "STANDARD")

        kubernetes_groups = optional(list(string))
        user_name         = optional(string)

        policy_associations = map(object({
            policy_arn   = string
            access_scope = optional(object({
                type       = string
                namespaces = optional(list(string))
            }))
        }))
    }))
    default = {}
}

############
## Addons ##
############

variable "bootstrap_self_managed_addons" {
    description = "Install default unmanaged add-ons, such as aws-cni, kube-proxy, and CoreDNS during cluster creation. If false, you must manually install desired add-ons."
    type        = bool
    default     = true
}

variable "cluster_addons" {
  description = "Install cluster addons"
  type = map(object({
    version              = optional(string)
    configuration_values = optional(string)

    pod_identity_association = optional(object({
      role_arn        = string
      service_account = string
    }))

    preserve                    = optional(bool, false)
    resolve_conflicts_on_create = optional(string)
    resolve_conflicts_on_update = optional(string)
    service_account_role_arn    = optional(string)

    before_compute = optional(bool, false)
  }))
}

#################
## Node Groups ##
#################

variable "node_groups" {
    type = map(object({
        instance_types = list(string)
        capacity_type  = optional(string, "ON_DEMAND")
        disk_size      = optional(string)
        subnet_ids     = list(string)

        ami_type                       = optional(string)
        ami_release_version            = optional(string)
        use_latest_ami_release_version = optional(bool, false)

        version              = optional(string)    # Not neccessary if using AMI
        force_update_version = optional(bool)

        scaling = object({
            min_size     = number
            max_size     = number
            desired_size = optional(number)
        })

        ssh_access = optional(object({
            ssh_key           = string
            security_group_id = optional(string) 
        }))

        enable_node_repair = optional(bool)
        update_config = optional(object({
            max_unavailable_percentage = optional(number)
            max_unavailable            = optional(number)
        }))

        labels = optional(map(string))
        taints = optional(list(object({
            key    = string
            value  = optional(string)
            effect = string
        })), [])
    }))
    default = {}
}

variable "timeouts" {
    type = object({
        create = optional(number)
        update = optional(number)
        delete = optional(number)
    })
    default = null
}

variable "tags" {
    description = "Common tags"
    type        = map(string)
    default     = {}
}