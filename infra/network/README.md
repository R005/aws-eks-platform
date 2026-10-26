# network

Terraform stack that creates the VPC the EKS cluster runs in. It uses the community module [`terraform-aws-modules/vpc/aws`](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws) (major version 6).

State: `network/terraform.tfstate` in the bucket created by [`bootstrap`](../bootstrap/README.md). Apply order: `bootstrap → network → eks → addons`, destroy in reverse.

## Layout

| Subnet | CIDR | AZ | Holds |
| --- | --- | --- | --- |
| private | `10.0.0.0/20` | 1st AZ | worker nodes, pods, internal load balancers |
| private | `10.0.16.0/20` | 2nd AZ | worker nodes, pods, internal load balancers |
| public | `10.0.48.0/24` | 1st AZ | NAT Gateway, internet-facing load balancers |
| public | `10.0.49.0/24` | 2nd AZ | internet-facing load balancers |

- VPC `10.0.0.0/16`, the first two available AZs of the region.
- Private subnets are large (`/20`, 4,096 addresses) because the VPC CNI gives every pod an IP address from the subnet. Public subnets only hold the NAT Gateway and load balancers, so `/24` is enough.
- The rest of the `/16` is free for later use (for example database subnets for RDS).
- One NAT Gateway in the first public subnet. Both private subnets route `0.0.0.0/0` through it. See [ADR 0007](../../docs/adr/0007-single-nat-gateway-in-lab.md). Set `single_nat_gateway = false` for one NAT Gateway per AZ.
- DNS hostnames and DNS support are enabled. EKS nodes need both to register with their private DNS names.

## Resources

All resources come from `module.vpc`:

| Resource | Purpose |
| --- | --- |
| `aws_vpc.this` | The VPC, tagged `Name = <project>-<env>-vpc` so the `eks` stack can look it up |
| `aws_subnet.public` (x2) | Public subnets, tagged `kubernetes.io/role/elb = 1` |
| `aws_subnet.private` (x2) | Private subnets, tagged `kubernetes.io/role/internal-elb = 1` |
| `aws_internet_gateway.this` | Internet access for the public subnets |
| `aws_eip.nat` | Static public IP of the NAT Gateway |
| `aws_nat_gateway.this` | Outbound internet access for the private subnets |
| `aws_route_table.public`, `aws_route.public_internet_gateway` | Public route table with `0.0.0.0/0 → internet gateway` |
| `aws_route_table.private`, `aws_route.private_nat_gateway` | Private route table with `0.0.0.0/0 → NAT Gateway` |
| `aws_route_table_association.*` (x4) | Attach each subnet to its route table |
| `aws_default_network_acl.this`, `aws_default_route_table.default`, `aws_default_security_group.this` | Take over the VPC defaults; the default security group is left with no rules, so nothing uses it by accident |

| Data source | Purpose |
| --- | --- |
| `aws_availability_zones.available` | Picks the AZs without hardcoding names; excludes Local Zones |

All resources are tagged through the provider `default_tags`: `Project`, `Env`, `Owner`, `ManagedBy` (`terraform`) and `Stack` (`network`).

## Subnet tags

The AWS Load Balancer Controller chooses subnets for a load balancer by these tags:

| Tag | On | Used for |
| --- | --- | --- |
| `kubernetes.io/role/elb = 1` | public subnets | internet-facing ALBs and NLBs |
| `kubernetes.io/role/internal-elb = 1` | private subnets | internal ALBs and NLBs; the `eks` stack also finds the private subnets by this tag |

## Usage

Prerequisites: Terraform >= 1.11, the `bootstrap` stack applied, and an active AWS SSO session (`aws sso login`).

```bash
cp terraform.tfvars.example terraform.tfvars   # set owner
cp backend.hcl.example backend.hcl             # replace <account-id>

terraform init -backend-config=backend.hcl
terraform plan -out=tfplan
terraform apply tfplan
```

From the repository root, `make up` applies this stack and then `eks`.

## Inputs

| Variable | Default | Description |
| --- | --- | --- |
| `region` | (required) | AWS region |
| `owner` | (required) | Owner tag |
| `project` | `eks-platform` | Name prefix and `Project` tag |
| `env` | `dev` | Name part and `Env` tag |
| `vpc_cidr` | `10.0.0.0/16` | VPC CIDR; subnets are derived from it |
| `az_count` | `2` | Number of AZs |
| `single_nat_gateway` | `true` | One shared NAT Gateway, or one per AZ when `false` |

## Outputs

| Output | Description |
| --- | --- |
| `vpc_id` | VPC ID |
| `vpc_cidr` | VPC CIDR block |
| `azs` | AZs in use |
| `private_subnet_ids` | Private subnet IDs |
| `public_subnet_ids` | Public subnet IDs |
| `nat_gateway_ids` | NAT Gateway IDs |

## Cost and teardown

About $0.05 per hour while it exists: the NAT Gateway ($0.045/h plus $0.045/GB processed) and its public IPv4 address ($0.005/h). The VPC, subnets and route tables are free.

Destroy it at the end of every session, after the `eks` stack:

```bash
make down    # from the repository root: destroys eks, then network
```
