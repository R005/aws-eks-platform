# Excludes Local Zones and Wavelength Zones.
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  name = "${var.project}-${var.env}"
  azs  = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Private subnets are /20 because the VPC CNI gives every pod a VPC IP. Public subnets only hold
  # the NAT Gateway and load balancers, so /24 is enough.
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]      # 10.0.0.0/20, 10.0.16.0/20
  public_subnets  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, 48 + i)] # 10.0.48.0/24, 10.0.49.0/24
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7" # modules are not in the lock file, so pin here

  name = local.name
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  # EKS nodes register with private DNS hostnames.
  enable_dns_hostnames = true
  enable_dns_support   = true

  # The eks stack looks the VPC up by this name.
  vpc_tags = {
    Name = "${local.name}-vpc"
  }
  igw_tags = {
    Name = "${local.name}-igw"
  }

  # Subnet discovery for the AWS Load Balancer Controller. The eks stack also finds the private
  # subnets by the internal-elb tag.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}
