# Secrets Manager module

Creates AWS Secrets Manager secret metadata for runtime workloads. It intentionally does **not** create or manage secret versions/values.

## Security design

- Secret values must never be committed to Git, stored in Terraform variables, or passed through Terraform resources.
- Terraform creates only the secret container (name, description, tags, optional KMS key, recovery window).
- When no customer-managed KMS key is supplied, AWS Secrets Manager uses its AWS-managed encryption key.
- Secrets have a 7-day recovery window by default (configurable from 7 to 30 days).
- No resource policy grants public or cross-account access.
- ECS execution roles receive `secretsmanager:GetSecretValue` only for the exact secret ARNs supplied to the IAM module.
- The application receives the secret through ECS task-definition secret injection; it should read the environment variable at runtime and must never log it.

## E-commerce MongoDB Atlas secret

The Test Lab root creates the logical secret `ecommerce_mongodb_atlas_uri` at:

```text
dcc-testlab-use1/ecommerce/mongodb-atlas/uri
```

The Atlas connection URI is added separately after infrastructure review, using an approved secure method. It is not a Terraform-managed value and will not appear in Terraform state.

## Validation

```bash
terraform init -backend=false
terraform test
```

The mocked tests plan secret metadata only and do not create AWS resources or secret values.
