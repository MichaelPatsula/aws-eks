locals {
    eks_owned_tag = {
        "kubernetes.io/cluster/eks-name" = "owned"
    }
    eks_internal_elb_tag = {
        "kubernetes.io/role/elb" = "1"
    } 
}

provider "aws" {
  region = "ca-central-1"
}

data "aws_availability_zones" "this" {
  state = "available"
}

##########
# Module #
##########

module vpc {
    source = "git::ssh://git@github.com/MichaelPatsula/aws-vpc.git"
    name                    = "gen-canary-cc-00"
    cidr_blocks             = ["172.26.0.0/16", "172.27.0.0/16"]
    availability_zones      = [data.aws_availability_zones.this.zone_ids[0], data.aws_availability_zones.this.zone_ids[1]]
    enable_dns_hostnames    = true
    single_nat_gateway      = true

    subnets = {
        "transit-gateway" = {
            cidr_blocks        = ["172.26.1.0/24", "172.26.2.0/24"]
            subnet_type        = "public"
            create_nat_gateway = true    
        },
        "loadbalancer" = {
            cidr_blocks = ["172.26.3.0/24", "172.26.4.0/24"]
            subnet_type = "public"
            tags        = merge(local.eks_internal_elb_tag, local.eks_owned_tag) 
        },
        "control-plane" = {
            cidr_blocks = ["172.26.5.0/24", "172.26.6.0/24"]
            tags        = merge(local.eks_internal_elb_tag, local.eks_owned_tag) 
        },        
        "node-pools" = {
            cidr_blocks = ["172.26.7.0/24", "172.26.8.0/24"]
            tags        = local.eks_owned_tag
        },        
        "infrastructure" = {
            cidr_blocks         = ["172.26.9.0/24", "172.26.10.0/24"]
            gateway_endpoints   = {s3 = {}}
            interface_endpoints = {
                s3 = {}
            }                 
        }         
    }
}

module "vpc_flow_logs" {
    source = "../../terraform-aws-vpc-flow-logs"

    name                 = "gen-canary-cc-00"
    vpc_id               = module.vpc.vpc.id
    log_destination_type = "cloud-watch-logs"
}

locals {
  create_node_group = true
}

module "eks_cluster" {
  source  = "../"

  name            = "gen-canary-cc-00"
  cluster_version = "1.33"

  subnet_ids = module.vpc.subnet_id_map["control-plane"]
  vpc_id     = module.vpc.vpc.id

  bootstrap_self_managed_addons = false
  cluster_addons = local.create_node_group ? {
    eks-pod-identity-agent = {}
    coredns    = {}
    kube-proxy = {}
    # vpc-cni = {
    #   before_compute = true
    # }    
  } : {}

  api_server = {
    endpoint_private_access = false
    endpoint_public_access  = true
  }

  node_groups = local.create_node_group ? {
    system = {
      ami_type       = "AL2023_x86_64_STANDARD" #"BOTTLEROCKET_x86_64"
      instance_types = ["t3.small"]
      subnet_ids     = module.vpc.subnet_id_map["node-pools"]

      scaling = {
        min_size     = 1
        max_size     = 2
      }
      # bootstrap_extra_args = <<-EOT
      #   # The admin host container provides SSH access and runs with "superpowers".
      #   # It is disabled by default, but can be disabled explicitly.
      #   [settings.kubernetes]
      #   max-pods = 110

      #   # https://bottlerocket.dev/en/os/1.44.x/api/settings/pki/
      #   # [settings.pki.my-trusted-bundle]
      #   # data="W3N..."
      #   # trusted=true
      # EOT

      iam_role_additional_policies = {
        SSM = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }
    }
  } : {}
}

