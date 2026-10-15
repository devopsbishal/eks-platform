# eks-platform

Kubernetes on AWS, end to end: provision EKS with Terraform, deliver to it with GitHub Actions
and Argo CD, observe it with Prometheus, secure it with Pod Identity, then break it on purpose
and write down what happened.

Built in stages. Each stage ends in something that runs.

## Status

| Stage | What | Status |
|---|---|---|
| Bootstrap | S3 state bucket, AWS Budget alert | Done |
| Network and cluster | VPC and EKS through thin wrapper modules, managed node group, access entries | Next |
| Delivery | Argo CD app-of-apps; GitHub Actions builds, scans (Trivy) and pushes to ECR over OIDC | Planned |
| Observability | kube-prometheus-stack, an SLO with multi-window burn-rate alerts, one dashboard | Planned |
| Security | EKS Pod Identity for workloads | Planned |
| Game days | Failure write-ups with real numbers in `game-days/` | Planned |
| Cost | What it costs per hour and per month, and the cheaper version, in `COST.md` | Planned |

Argo CD, CI and observability are built and broken on a local Vagrant cluster first. EKS is applied
for the AWS-specific parts and for full integration runs, then destroyed. It costs money every hour
it is up.

## Layout

```
terraform/
  bootstrap/   state bucket and budget; applied once per account
```

## Bootstrap

```sh
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars   # set profile, bucket name, alert email
terraform init
terraform plan
terraform apply
```

Bootstrap creates the bucket that holds every other module's state, so it starts with local state
and is migrated into that bucket afterwards.

## Conventions

- State in S3 with native lockfile locking (`use_lockfile = true`), no DynamoDB table.
- Providers and modules pinned; `.terraform.lock.hcl` committed.
- Every resource tagged `environment`, `owner`, `cost-center`, `project`.
- No static AWS keys in CI: GitHub OIDC with the trust policy pinned to this repo and branch.
- `checkov` and `trivy config` run over `terraform/`. Every finding is fixed or suppressed with a
  written reason next to the suppression.
- No state, plans, real `.tfvars`, kubeconfigs, account IDs or secrets in the repo. Commits are
  scanned with gitleaks.
