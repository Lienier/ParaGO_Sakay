# ParaGO AWS Staging

This directory is the AWS-first staging foundation for ParaGO. It is intentionally
split into two Terraform roots:

- `bootstrap/` creates the encrypted S3/KMS remote-state foundation.
- `envs/staging/` creates the isolated AWS staging backend environment.

Do not run `terraform apply` until AWS identity, MFA, billing alerts, and the
pricing estimate have been reviewed and approved.

## Local Prerequisites

Install these on Windows before planning:

- AWS CLI v2
- Terraform CLI

Then authenticate without pasting secrets into chat:

```powershell
aws sts get-caller-identity
```

Expected region for all ParaGO AWS staging resources is `ap-southeast-1`.

## Bootstrap State

The bootstrap root uses local state only long enough to create the encrypted S3
state bucket and KMS key.

```powershell
cd infra/aws/bootstrap
terraform init
terraform plan -out bootstrap.tfplan
```

Review the plan before applying. After approval:

```powershell
terraform apply bootstrap.tfplan
```

Copy the output bucket name into
`infra/aws/envs/staging/backend.hcl` using `backend.hcl.example` as the template.

## Staging Plan

From `infra/aws/envs/staging`:

```powershell
terraform init -backend-config backend.hcl
terraform plan -out staging.tfplan
```

Stop here for review and cost approval before any `terraform apply`.

For thesis development, treat staging as temporary infrastructure. Stopping the
EC2 instance does not stop NAT Gateway, Valkey, KMS, CloudFront, or storage
charges. Use Terraform to destroy staging when testing is complete:

```powershell
cd infra/aws/envs/staging
terraform destroy -var ami_id=ami-0ed6a65b84536f6ce
```

Do not destroy the bootstrap state bucket unless the AWS migration work is fully
abandoned and you have exported any evidence you need.

## Secrets

Do not commit `backend.hcl`, `*.tfvars`, `*.tfplan`, `.terraform/`, Terraform
state, access keys, session tokens, MongoDB URIs, Redis auth tokens, JWT secrets,
or service credentials.

Runtime secrets are expected in SSM Parameter Store under:

```text
/parago/staging/aws/v1/
```

The EC2 role may read only that staging path.

## GitHub Actions Deploy

The bootstrap root also creates an OIDC deploy role for this repository:

```text
arn:aws:iam::<account-id>:role/parago-github-staging-deploy
```

After bootstrap has been applied, pushes to `main` run
`.github/workflows/aws-staging-deploy.yml`. The workflow packages the committed
backend source, uploads it to the state bucket under `parago/staging/releases/`,
then uses Systems Manager to deploy the release onto the private EC2 instance.

The workflow expects staging to already be on. If `terraform destroy` has been
used, turn staging on again first:

```powershell
cd infra/aws/envs/staging
terraform apply -var ami_id=ami-0ed6a65b84536f6ce
```

Because the current setup uses the generated CloudFront hostname, turning
staging off and on can produce a new client URL. Update the Flutter
`awsApiBaseUrl` constants or move to a custom domain before relying on automatic
client builds.

## Current Design Notes

- Region: Singapore, `ap-southeast-1`
- EC2: private subnet, no public IPv4, no SSH rule
- Administration: AWS Systems Manager Session Manager
- Ingress: CloudFront generated HTTPS hostname to a private VPC origin
- Cache: private ElastiCache/Valkey-compatible Redis with TLS and auth token
- MongoDB: Atlas remains the durable database
- Redis namespace: `parago:staging:aws:v1`
- API and worker run as separate `systemd` services from the same release
