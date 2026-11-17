# network

The VPC the cluster runs in, built with [`terraform-aws-modules/vpc/aws`](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws) v6.

| Subnet | CIDR | Holds |
| --- | --- | --- |
| private, AZ 1 | `10.0.0.0/20` | nodes, pods, internal load balancers |
| private, AZ 2 | `10.0.16.0/20` | nodes, pods, internal load balancers |
| public, AZ 1 | `10.0.48.0/24` | NAT Gateway, internet-facing load balancers |
| public, AZ 2 | `10.0.49.0/24` | internet-facing load balancers |

The private subnets are large because the VPC CNI gives every pod a VPC address. The rest of the `/16` is free, for example for RDS subnets later. One NAT Gateway serves both AZs ([ADR 0007](../../docs/adr/0007-single-nat-gateway-in-lab.md)); set `single_nat_gateway = false` for one per AZ.

Subnets carry the `kubernetes.io/role/elb` (public) and `kubernetes.io/role/internal-elb` (private) tags that the Load Balancer Controller uses to place load balancers. The `eks` stack finds the VPC by its `Name` tag and the private subnets by the `internal-elb` tag, so it never reads this stack's state.

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars   # set owner
cp backend.hcl.example backend.hcl             # replace <account-id>
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan
terraform apply tfplan
```

Normally `make up` applies it, followed by `eks` and `addons`.

## Cost and teardown

About $0.05 per hour for the NAT Gateway and its public IP, plus $0.045 per GB processed. `make down` destroys it last, after `addons` and `eks`.
