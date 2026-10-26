# Only AZs that are fully available (excludes Local Zones and Wavelength Zones).
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  name = "${var.project}-${var.env}" # eks-platform-dev
  azs  = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Private subnets are /20 (4,096 IPs each): the VPC CNI gives every pod a VPC IP, so they need room.
  # Public subnets are /24 (256 IPs each): they only hold the NAT Gateway and load balancers.
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]      # 10.0.0.0/20, 10.0.16.0/20
  public_subnets  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, 48 + i)] # 10.0.48.0/24, 10.0.49.0/24
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7" # any 6.x from 6.7 on; the module source is not in the lock file, so pin it here

  name = local.name
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  # Egress for the private subnets.
  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  # Required by EKS: nodes register with private DNS hostnames.
  enable_dns_hostnames = true
  enable_dns_support   = true

  # The eks stack looks the VPC up by this name.
  vpc_tags = {
    Name = "${local.name}-vpc"
  }
  igw_tags = {
    Name = "${local.name}-igw"
  }

  # Subnet discovery for the AWS Load Balancer Controller.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1" # internet-facing load balancers
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1" # internal load balancers; the eks stack also uses it to find the private subnets
  }
}
