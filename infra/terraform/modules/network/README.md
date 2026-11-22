# Network Module

## Purpose

Creates the isolated network foundation required by DCC and its Test Lab:

- One VPC with DNS support and DNS hostnames enabled.
- Two public subnets for internet-facing infrastructure such as a future ALB and NAT Gateway.
- Two private application subnets for ECS workloads.
- Two private data subnets for RDS and ElastiCache.
- An Internet Gateway and public default route.
- One optional NAT Gateway and a default route for private application subnets.
- Separate route tables for public, private application, and private data tiers.

This module does **not** create Security Groups, ECS, ALB, RDS, Redis, VPC endpoints, or cross-VPC connectivity.

## Traffic model

```text
Internet
   |
Internet Gateway
   |
Public Subnets ------------------ NAT Gateway
   |                                  |
Future public ALB               Private App Subnets
                                      |
                                ECS workloads

Private Data Subnets
   |
Local VPC traffic only (no default internet route)
```

The private application tier uses one NAT Gateway when `enable_nat_gateway = true`. This is a cost-conscious lab design, not a highly available production egress design: both AZs depend on one NAT Gateway in the first public subnet. Disabling NAT removes the private application default route; it does not create an alternative egress path.

## Inputs

| Input | Meaning |
|---|---|
| `name_prefix` | Stable prefix for AWS Name tags |
| `vpc_cidr` | Dedicated IPv4 VPC CIDR |
| `availability_zones` | Empty to select two available AZ names, or exactly two explicit names |
| `public_subnet_cidrs` | Two public subnet ranges |
| `private_application_subnet_cidrs` | Two private app ranges |
| `private_data_subnet_cidrs` | Two private data ranges |
| `enable_nat_gateway` | Whether to create the NAT Gateway |
| `tags` | Additional non-sensitive tags |

All subnet CIDRs are ordered to correspond to the two selected AZs. Preconditions verify that subnet ranges fit within the VPC and do not overlap each other.

## Outputs

- `vpc_id`, `vpc_cidr`
- `availability_zones`
- `public_subnet_ids`
- `private_application_subnet_ids`
- `private_data_subnet_ids`
- `nat_gateway_id`
- `route_table_ids`

## Example

```hcl
module "network" {
  source = "../modules/network"

  name_prefix = "dcc-testlab-use1"
  vpc_cidr    = "10.81.0.0/16"

  availability_zones = []

  public_subnet_cidrs = [
    "10.81.0.0/24",
    "10.81.1.0/24",
  ]

  private_application_subnet_cidrs = [
    "10.81.16.0/20",
    "10.81.32.0/20",
  ]

  private_data_subnet_cidrs = [
    "10.81.48.0/24",
    "10.81.49.0/24",
  ]

  enable_nat_gateway = true
  tags               = {
    Project     = "DCC-TestLab"
    Environment = "lab"
    ManagedBy   = "Terraform"
  }
}
```

## Cost and security notes

- NAT Gateway hourly and data-processing charges apply when enabled; one NAT is a single-AZ dependency.
- Public subnets do not automatically assign public IPs to launched instances.
- Private application subnets have outbound internet routing only through NAT; they do not have direct inbound internet routes.
- Private data subnets have no default internet route.
- A route table is not a firewall. Security Groups and Network ACLs are separate controls.
- CIDR validation checks subnet containment and subnet-to-subnet overlap inside the module. It cannot detect overlap with unrelated VPCs, VPNs, Transit Gateways, office networks, or customer networks; that remains a pre-deployment review.
