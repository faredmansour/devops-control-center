# ECR repositories module

Creates four private Amazon ECR repositories for the isolated DCC Test Lab:

| Workload key | Repository suffix | Intended image |
|---|---|---|
| `dcc` | `dcc` | DCC Control Plane |
| `ecommerce` | `ecommerce` | E-commerce application image(s) |
| `agent` | `agent` | Reusable DCC Integration Agent |
| `test_worker` | `test_worker` | On-demand test worker image |

Repository names are prefixed with the supplied `name_prefix`.

## Security and retention defaults

- Private repositories; no public repository is created.
- Image tag mutability is `IMMUTABLE` to prevent silently replacing an existing tag.
- Scan on push is enabled.
- Images are encrypted at rest with ECR-managed AES-256 encryption.
- Lifecycle policy retains the 10 most recent images in each repository.
- `force_delete = false` protects repositories from being deleted while images remain.
- No repository policy grants cross-account or anonymous access. ECS pulls are authorized by the workload-specific IAM execution roles.

## IAM integration

The module exports repository ARNs keyed by workload. The Test Lab root passes these directly to the IAM module, so each ECS execution role can pull only its own repository. ECR authorization-token retrieval remains the one required action with Resource `*`.

## Validation

The Terraform native tests use a mocked AWS provider and do not create AWS resources:

```bash
terraform init -backend=false
terraform test
```

This module creates repository infrastructure only. It does not build, tag, or push container images.
