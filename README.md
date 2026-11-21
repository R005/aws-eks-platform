# aws-eks-platform

An EKS platform built with Terraform and Helm. It runs a small FastAPI task tracker backed by PostgreSQL at `https://tasks.lab.<domain>`. The app is deliberately small; the work is in the platform around it.

## Architecture

```text
                              Internet
                                 |
                                 |  https://<app>.lab.<domain>
                                 v
             Route 53 hosted zone: lab.<domain>  (records by ExternalDNS)
                                 |
+- VPC (us-east-1) ------------------------------------------------------+
| Public subnets (2 AZs)                                                 |
|  +--------------------------------+      +--------------------+        |
|  | ALB (Ingress via AWS LBC)      |      | NAT Gateway (x1)   |        |
|  | TLS: ACM certificate           |      |                    |        |
|  +--------------------------------+      +--------------------+        |
|                 |                                   ^                  |
| Private subnets | HTTPS -> api                      | egress           |
|  +------------------------------------------------------------------+  |
|  | EKS managed node group (amd64)                                   |  |
|  |                                                                  |  |
|  |  ns tasks:                                                       |  |
|  |    [api: FastAPI] --> [postgres: StatefulSet]                    |  |
|  |                             |                                    |  |
|  |                       PVC (EBS gp3)                              |  |
|  |                                                                  |  |
|  |  platform add-ons: AWS LBC, ExternalDNS, External Secrets,       |  |
|  |                    EBS CSI, metrics-server,                      |  |
|  |                    kube-prometheus-stack                         |  |
|  +------------------------------------------------------------------+  |
+------------------------------------------------------------------------+

  GitLab.com CI --build/push (multi-arch)--> ECR --pull--> nodes
        \------- helm upgrade --install -----------------> EKS API
  AWS Secrets Manager --(External Secrets + IRSA)--> Kubernetes Secrets
  S3 bucket: Terraform state (S3 native locking)
```

kube-prometheus-stack is not built yet. Decisions are recorded in [`docs/adr/`](docs/adr/README.md).

```text
apps/api/             FastAPI service, Dockerfile, OPERATIONS.md
helm/task-tracker/    Chart for the api, Postgres, migrations, Ingress and secrets
infra/bootstrap/      State bucket and KMS key (kept)
infra/foundation/     ECR, database secret, lab.<domain> zone and certificate, CI role (kept)
infra/network/        VPC, subnets, NAT Gateway
infra/eks/            Cluster, node group, OIDC provider, access entries
infra/addons/         EBS CSI, Load Balancer Controller, External Secrets, metrics-server, ExternalDNS, tasks namespace
scripts/              check-cluster-clean.sh, run by make down
.gitlab-ci.yml        Pipeline: lint, test, build, scan, push, deploy
docs/adr/             Architecture Decision Records
```

Each Terraform stack is its own root module with its own state.

## Prerequisites

```bash
brew install awscli terraform kubectl helm pre-commit tflint gitleaks direnv uv
```

You also need Docker with buildx and Compose v2, and Terraform 1.11 or later. AWS access goes through IAM Identity Center only; there are no access keys and no default profile.

```bash
aws configure sso                            # profile name: lab-dev
echo 'export AWS_PROFILE=lab-dev' > .envrc   # gitignored
direnv allow
aws sso login                                # again whenever the token expires
```

```bash
pre-commit install                           # pre-commit and commit-msg hooks
```

Commits follow Conventional Commits and land on `main` through a merge request ([ADR 0009](docs/adr/0009-trunk-based-git-workflow.md)).

## Local development

Compose starts `postgres`, runs the one-shot `migrate` container, then starts `api`. No AWS access is needed.

```bash
cp .env.example .env
sed -i '' "s|^DB_PASSWORD=$|DB_PASSWORD=$(openssl rand -base64 24)|" .env
docker compose up --build -d
docker compose ps -a                         # postgres healthy, migrate exited (0), api healthy

curl -s localhost:8000/readyz
curl -s -XPOST localhost:8000/tasks -H 'content-type: application/json' -d '{"title":"first task"}'
curl -s localhost:8000/tasks
```

The api listens on `127.0.0.1:8000`. Postgres is not published; use `docker compose exec postgres psql -U tasks tasks`. For stress drills, set `ENABLE_DEBUG_ENDPOINTS=true` in `.env` and run `docker compose up -d api`.

`docker compose down` stops the stack and keeps the data; add `-v` to delete it.

Unit tests use in-memory SQLite, so they need neither Postgres nor Docker:

```bash
cd apps/api && uv run pytest
```

The api's runtime contract (env vars, probes, shutdown, logs, metrics) is in [`apps/api/OPERATIONS.md`](apps/api/OPERATIONS.md).

## Deploy to EKS

| Step | Command | When |
| --- | --- | --- |
| 1 | `bootstrap` stack ([README](infra/bootstrap/README.md)) | once per account |
| 2 | `foundation` stack ([README](infra/foundation/README.md)), then delegate `lab.<domain>` | once |
| 3 | `make image` | after each change to `apps/api` (commit it first) |
| 4 | `make up` | start of each session |
| 5 | `aws eks update-kubeconfig --region <region> --name eks-platform-dev` | after each `make up` |
| 6 | `make deploy` | after `make up` and after each new image |
| 7 | `make undeploy`, then `make down` | end of each session |

`make image` builds `linux/amd64` (emulated on Apple Silicon), tags it with the short Git SHA and pushes it to ECR. Tags are immutable, so it refuses to run while `apps/api` has uncommitted changes.

`make deploy` checks that the tag exists in ECR, then runs `helm upgrade --install` with the registry, tag, region and host on the command line. Use `TAG=<sha>` to deploy an earlier image, `APP_HOST=...` to override the host, and `HELM_ARGS` for extra Helm flags, for example `HELM_ARGS="--set debugEndpoints.enabled=true"`. A plain `make deploy` resets them.

`make undeploy` asks for confirmation, uninstalls the release and deletes the Postgres PVC with its data. `deploy` and `undeploy` always pass the `eks-platform-dev` kube context, so they never touch another cluster.

```bash
kubectl -n tasks get externalsecret,pods,svc,pvc,ingress
curl -sI http://tasks.lab.<domain>/readyz    # 301 to https
curl -s https://tasks.lab.<domain>/readyz
```

The ALB and its DNS record take a few minutes on the first deploy.

## CI/CD

Merge request pipelines run ruff, `terraform fmt -check`, `helm lint`, the unit tests, an image build and a Trivy scan, with no AWS access. Pipelines on `main` run the same, push the scanned image to ECR tagged with `$CI_COMMIT_SHORT_SHA`, and offer a manual `deploy-dev` job that runs `helm upgrade --install` with the same values as `make deploy` and rolls back on failure. The image is built once with rootless BuildKit as an OCI layout and passed between jobs as an artifact, so the pushed digest is the scanned one. Trivy fails the pipeline on HIGH or CRITICAL vulnerabilities that have a fix.

Jobs on `main` get AWS credentials through GitLab OIDC ([ADR 0016](docs/adr/0016-ci-authentication-with-gitlab-oidc.md)). Set these protected CI/CD variables: `AWS_ACCOUNT_ID` (masked), `AWS_REGION`, `AWS_ROLE_ARN` (masked, from `terraform -chdir=infra/foundation output -raw ci_role_arn`) and `APP_HOST` (masked). `make image` uses the same 8-character short SHA, so local and CI tags match.

`deploy-dev` only works while the platform is up, and the first run of a session needs no local `make deploy` because `addons` creates the namespace.

## Cost and teardown

Approximate us-east-1 on-demand prices with everything running:

| Resource | Cost |
| --- | --- |
| EKS control plane | $0.10/h, about $73/month |
| NAT Gateway | $0.045/h plus $0.045/GB, about $33/month |
| 2 x t3.large nodes | about $121/month |
| ALB | about $16/month plus LCUs |
| Public IPv4 (NAT, ALB) | about $11/month |
| EBS gp3 (node root volumes, Postgres PVC) | a few $/month |
| Route 53, Secrets Manager, ECR, S3, KMS, CloudWatch Logs | about $3-5/month |
| Total | about $265/month, $8-9 per day |

A single NAT Gateway ([ADR 0007](docs/adr/0007-single-nat-gateway-in-lab.md)), a small node group and in-cluster Postgres ([ADR 0002](docs/adr/0002-postgres-statefulset-first-rds-later.md)) keep this down; production would cost noticeably more. Keep the cluster on a version in standard support, because extended support costs $0.60/h.

Destroy the platform at the end of every session:

```bash
make undeploy
make down
```

`make down` first runs `check-clean`, which fails while the release or any Ingress, LoadBalancer Service or PVC still exists. Their controllers create load balancers and EBS volumes outside Terraform, and destroying `addons` first would orphan them. `bootstrap` and `foundation` are kept: they cost almost nothing and DNS delegation is slow to redo. Afterwards, check the console for leftover load balancers, volumes, ENIs and Elastic IPs.

## Roadmap

- [x] M0-M1: repository, pre-commit, ADRs
- [x] M2: `bootstrap` state bucket
- [x] M3: `network` VPC
- [x] M4: `eks` cluster
- [x] M5: `addons` (EBS CSI, Load Balancer Controller, External Secrets, metrics-server)
- [x] M6: api, Dockerfile, Compose, `foundation` (ECR, secret), `make image`
- [x] M7: `task-tracker` chart and `make deploy`
- [x] M8: GitLab CI: lint, test, build, scan, push, deploy
- [x] M9: HTTPS at `tasks.lab.<domain>`
- [ ] M10: kube-prometheus-stack, dashboards, alerts
- [ ] M11: move PostgreSQL to RDS
- [ ] M12: NetworkPolicies, Pod Security Admission, image scanning

## Security

- No long-lived AWS credentials. People use IAM Identity Center, pods use IRSA ([ADR 0005](docs/adr/0005-irsa-for-pod-aws-access.md)), and CI uses GitLab OIDC on `main` only ([ADR 0016](docs/adr/0016-ci-authentication-with-gitlab-oidc.md)).
- Secrets live in Secrets Manager and reach pods through External Secrets ([ADR 0004](docs/adr/0004-external-secrets-operator.md)), never through Git, Helm values or CI logs.
- Each controller has its own IAM role, scoped to its ServiceAccount.
- Nodes run in private subnets; only the ALB is internet-facing.
- Terraform state is in an encrypted, versioned bucket and is never committed or printed.
- gitleaks and detect-private-key run on every commit.
- The repo is mirrored publicly, so it only uses placeholders such as `<domain>` and `<account-id>`.
- Every AWS resource is tagged `Project`, `Env`, `Owner` and `ManagedBy` through provider `default_tags`.
