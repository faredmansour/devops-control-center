# DCC Test Lab — us-east-1 (Independent Environment)

**Status: preparation/review only — not deployable yet.**

This directory records the proposed inputs and security design for a second, independent Test Lab in AWS `us-east-1`. The existing Test Lab in `eu-north-1` must remain untouched.

## Isolation requirements

- Separate Terraform root/state and a distinct remote backend key.
- Distinct AWS resource names and tags (prefix: `dcc-testlab-use1`).
- New VPC/subnets/security groups in `us-east-1`; no IDs or endpoints copied from the Stockholm environment.
- No Terraform workspace/state sharing with `infra/terraform/test-lab`.
- No apply, import, destroy, or state migration against the existing environment.
- Images must be pushed to ECR in `us-east-1`; image digests from another region are not automatically available.

## Files

- `terraform.tfvars.example`: proposed non-secret region/network values.
- `SECURITY_GROUPS_DESIGN.md`: proposed traffic matrix and security review gates.

## Important blockers before this can become an executable Terraform root

The existing stack in `infra/terraform/test-lab` includes interdependent resources for VPC, NAT, security groups, IAM, ECR, Cloud Map, RDS, Redis, ECS, DCC and diagnostic execution. This directory intentionally does not pretend that a variables file alone is a complete Terraform root. The next implementation step is to create a full independent root (or a reusable module instantiated with separate state), audit every region-scoped dependency, and validate the complete plan.

## Required inputs not yet approved

1. CIDR overlap review for `10.81.0.0/16` against all VPCs, VPNs, peering/TGW routes, office networks and connected customer networks.
2. Approved DCC ingress source CIDRs or VPN range; fail closed until supplied.
3. ACM certificate ARN/domain for HTTPS in `us-east-1`.
4. Confirmed image digests pushed into the new region's ECR repositories.
5. Approved remote Terraform backend bucket/key and IAM permissions.

## Cost and safety

The existing design includes a NAT Gateway, ECS/Fargate, RDS and ElastiCache. A second copy incurs additional recurring charges. Cost must be reviewed before apply. No AWS resource is created by adding these files.
