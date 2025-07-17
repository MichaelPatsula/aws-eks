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

module "eks_cluster" {
  source  = "../"

  name            = "gen-canary-cc-00"
  cluster_version = "1.31"

  subnet_ids = module.vpc.subnet_id_map["control-plane"]    #[module.vpc.subnets["control-plane-az1"].id, module.vpc.subnets["control-plane-az2"].id]

  cluster_addons = {
    eks-pod-identity-agent = {}
  }

  api_server = {
    endpoint_private_access = false
    endpoint_public_access  = true
  }

  node_groups = {
    system = {
      ami_type       = "AL2_x86_64"
      instance_types = ["t3.medium"]
      subnet_ids     = module.vpc.subnet_id_map["node-pools"]  #[module.vpc.subnets["node-pools-az1"].id, module.vpc.subnets["node-pools-az2"].id]

      scaling = {
        min_size     = 1
        max_size     = 2
      }
    }
  }
}

