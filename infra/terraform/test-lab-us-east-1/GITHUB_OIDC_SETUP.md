# GitHub Actions OIDC for Test Lab ECR publishing

This is a one-time AWS IAM setup. It creates no application resources and does not deploy the Test Lab.

## 1. OIDC identity provider

In AWS IAM → Identity providers, create this provider only if it does not already exist:

- Provider URL: `https://token.actions.githubusercontent.com`
- Audience: `sts.amazonaws.com`

## 2. Create two separate IAM roles

Use a separate role per repository. Replace `<AWS_ACCOUNT_ID>` in the federated principal with the AWS account ID that owns the ECR repositories.

**DCC role trust policy** (for repository `faredmansour/devops-control-center`):

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::<AWS_ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
        "token.actions.githubusercontent.com:sub": "repo:faredmansour/devops-control-center:ref:refs/heads/feat/test-lab-us-east-1-isolated"
      }
    }
  }]
}
```

**E-commerce role trust policy** (for repository `faredmansour/ecommerce-project`):

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::<AWS_ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
        "token.actions.githubusercontent.com:sub": "repo:faredmansour/ecommerce-project:ref:refs/heads/feat/aws-testlab-deployment"
      }
    }
  }]
}
```

## 3. Attach the least-privilege ECR push policy

Attach this policy to each role, changing the repository name to the one assigned to that role. It grants image upload only; it does not grant ECS deployment or infrastructure permissions.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "GetEcrLoginToken",
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*"
    },
    {
      "Sid": "PushOnlyTheAssignedTestLabRepository",
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage"
      ],
      "Resource": "arn:aws:ecr:us-east-1:<AWS_ACCOUNT_ID>:repository/dcc-testlab-use1-dcc"
    }
  ]
}
```

For the E-commerce role, change the repository suffix to `dcc-testlab-use1-ecommerce`.

## 4. Add GitHub repository variables

In each repository, open Settings → Secrets and variables → Actions → Variables and add:

- Variable name: `AWS_ROLE_ARN`
- Value: the ARN of the role created for that repository.

Do not use long-lived AWS access keys. Do not add application secrets to GitHub.

## 5. Run the image workflows manually

- DCC repository → Actions → **Build and push DCC image to Test Lab ECR**.
- E-commerce repository → Actions → **Build and push E-commerce images to Test Lab ECR**.

The workflow summaries show the immutable image tags to copy into the local, uncommitted Test Lab `terraform.tfvars`. The workflows do not run Terraform and do not start ECS services.
