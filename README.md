# aws-eks-platform

A production-style platform on **AWS EKS**, built entirely with code (Terraform, Helm, GitLab CI). It runs a small Python 3-tier **task tracker**:

- **web**: FastAPI service that serves the UI and calls the api
- **api**: FastAPI service with the REST API and business logic
- **db**: PostgreSQL (a StatefulSet first, RDS later, see [ADR 0002](docs/adr/0002-postgres-statefulset-first-rds-later.md))

The app is deliberately small. The point of the project is the platform around it: networking, cluster, add-ons, secrets, CI/CD, DNS/TLS and observability, built the way a real team would build them.

> Status: **in progress**. The `api` service runs locally with Docker Compose. The `bootstrap`, `network` and `eks` Terraform stacks exist; add-ons, Helm charts and CI are next. See the [Roadmap](#roadmap).

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
|  | ALB (Gateway API via AWS LBC)  |      | NAT Gateway (x1)   |        |
|  | TLS: ACM certificate           |      |                    |        |
|  +--------------------------------+      +--------------------+        |
|                 |                                   ^                  |
| Private subnets | HTTPS -> web                      | egress           |
|  +------------------------------------------------------------------+  |
|  | EKS managed node group (amd64)                                   |  |
|  |                                                                  |  |
|  |  ns task-tracker:                                                |  |
|  |    [web: FastAPI] --> [api: FastAPI] --> [postgres: StatefulSet] |  |
|  |                                                |                 |  |
|  |                                          PVC (EBS gp3)           |  |
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

Traffic flow: client → Route 53 → ALB (provisioned by the AWS Load Balancer Controller from Gateway API resources) → `web` → `api` → `postgres`. Nodes sit in private subnets and reach the internet through the NAT Gateway.

Key decisions are recorded as ADRs in [`docs/adr/`](docs/adr/README.md).

## Tech stack

| Area | Tools |
| --- | --- |
| Cloud | AWS: VPC, EKS, ECR, Route 53, ACM, Secrets Manager, S3, IAM |
| Infrastructure as Code | Terraform (stacks: `bootstrap`, `network`, `eks`, `addons`) |
| Packaging and deploy | Docker (buildx, multi-arch), Helm, GitLab CI/CD (GitLab.com shared runners) |
| Application | Python, FastAPI, PostgreSQL |
| Cluster add-ons | AWS Load Balancer Controller (Gateway API), ExternalDNS, External Secrets Operator, EBS CSI driver, metrics-server |
| Observability | kube-prometheus-stack (Prometheus, Grafana, Alertmanager) |
| Quality and security | pre-commit, gitleaks, tflint, ruff, Conventional Commits |

## Repo layout (planned)

> Partly built. `apps/api/`, `infra/bootstrap/`, `infra/network/`, `infra/eks/`, `docker-compose.yml`, `Makefile`, `docs/adr/` and the repo tooling exist today; the rest is planned.

```text
.
├── apps/
│   ├── web/                  # FastAPI web service + Dockerfile (planned)
│   └── api/                  # FastAPI api service + Dockerfile, OPERATIONS.md
├── helm/
│   ├── web/                  # Helm chart (+ values-dev.yaml)
│   ├── api/
│   └── postgres/             # StatefulSet, headless Service, PVC template
├── infra/                    # Terraform: one root module (and one state file) per stack
│   ├── modules/              # reusable modules
│   ├── bootstrap/            # S3 state bucket + KMS key, README.md
│   ├── network/              # VPC, subnets, NAT Gateway, README.md
│   ├── eks/                  # EKS cluster, managed node group, OIDC provider, access entries, README.md
│   └── addons/               # Helm releases for cluster add-ons + IRSA roles
├── docs/adr/                 # Architecture Decision Records
├── .gitlab-ci.yml            # CI/CD pipeline
├── Makefile                  # make up / make down for the network and eks stacks
├── docker-compose.yml        # local stack: postgres, migrate, api
├── .env.example              # template for the gitignored .env
├── .pre-commit-config.yaml
├── CLAUDE.md
└── README.md
```

## Prerequisites

Tools (macOS, Homebrew):

```bash
brew install awscli terraform kubectl helm pre-commit tflint gitleaks direnv uv
# Docker Desktop (or another engine) with buildx and Compose v2, for local runs and multi-arch builds
```

- Terraform **>= 1.11** (S3 native state locking, see [ADR 0003](docs/adr/0003-s3-native-state-locking.md))
- AWS access goes through **IAM Identity Center (SSO)** only. There are no access keys and no default profile.

AWS profile through direnv:

```bash
aws configure sso                     # create the profile, named: lab-dev
echo 'export AWS_PROFILE=lab-dev' > .envrc   # .envrc is gitignored
direnv allow
aws sso login                         # run again whenever the token expires
aws sts get-caller-identity           # check which identity is active
```

The Terraform provider blocks never hardcode a profile, account ID or region. All of those come from the environment and variables.

## Local development

The `api` runs locally with Docker Compose: `postgres` starts and becomes healthy, a one-shot `migrate` container applies the Alembic migrations, then `api` starts. No AWS access is needed.

### Run the stack

```bash
cp .env.example .env                       # .env is gitignored
sed -i '' "s|^DB_PASSWORD=$|DB_PASSWORD=$(openssl rand -base64 24)|" .env   # generate a password
docker compose up --build -d
docker compose ps -a                       # postgres healthy, migrate exited (0), api healthy
```

Compose refuses to start while `DB_PASSWORD` is empty. The api listens on `127.0.0.1:8000` only, and Postgres is not published to the host (`docker compose exec postgres psql -U tasks tasks` for a shell).

### Try it

```bash
curl -s localhost:8000/healthz                       # liveness
curl -s localhost:8000/readyz                        # readiness (checks the database)
curl -s -XPOST localhost:8000/tasks -H 'content-type: application/json' -d '{"title":"first task"}'
curl -s localhost:8000/tasks
curl -s -XPATCH localhost:8000/tasks/1 -H 'content-type: application/json' -d '{"done":true}'
curl -s -XDELETE localhost:8000/tasks/1
curl -s localhost:8000/metrics | grep '^http_requests_total'
docker compose logs -f api                           # JSON logs
```

Stress drills (for autoscaling and OOM tests later): set `ENABLE_DEBUG_ENDPOINTS=true` in `.env`, run `docker compose up -d api`, then `curl -XPOST 'localhost:8000/debug/load/cpu?seconds=30&workers=2'` and watch `docker stats`. Set it back to `false` afterwards.

The runtime contract (env vars, probes, shutdown, logs, metrics, resource usage) is in [`apps/api/OPERATIONS.md`](apps/api/OPERATIONS.md).

### Unit tests

```bash
cd apps/api
uv run pytest            # installs Python 3.13 and the locked dev dependencies on first run
```

The tests use an in-memory SQLite database, so they need neither Postgres nor Docker.

### Stop and clean up

```bash
docker compose down        # stop and remove containers; keeps the pgdata volume
docker compose down -v     # also delete the database volume (all local data)
```

Local only, no AWS cost.

### Files

| File | Purpose |
| --- | --- |
| `docker-compose.yml` | Local stack: `postgres` (healthcheck, `pgdata` volume), one-shot `migrate`, hardened `api` |
| `.env.example` | Template for the gitignored `.env`; lists every variable, `DB_PASSWORD` left empty |
| `apps/api/Dockerfile` | Multi-stage build: uv + Debian builder, distroless non-root runtime, digest-pinned bases |
| `apps/api/.dockerignore` | Keeps tests, caches, local venvs and `.env` out of the build context |
| `apps/api/pyproject.toml` | Dependencies, Python version, ruff and pytest settings |
| `apps/api/uv.lock` | Exact, hashed versions of every dependency |
| `apps/api/OPERATIONS.md` | Operational contract: port, env vars, probes, migrations, shutdown, logs, metrics, resources |
| `apps/api/alembic.ini` | Points Alembic at `migrations/`; holds no connection details |
| `apps/api/migrations/env.py` | Runs migrations with the api's settings and JSON logging |
| `apps/api/migrations/script.py.mako` | Template for new migration files |
| `apps/api/migrations/versions/` | Versioned schema migrations (`0001` creates `tasks`) |
| `apps/api/src/api/__init__.py`, `routes/__init__.py` | Package markers |
| `apps/api/src/api/__main__.py` | Entrypoint: uvicorn with JSON logs and a 20 s graceful shutdown |
| `apps/api/src/api/main.py` | App factory: lifespan, request logging and metrics middleware, routers |
| `apps/api/src/api/config.py` | Settings from environment variables; the password is required and never echoed |
| `apps/api/src/api/log_config.py` | JSON log formatter and logging config for the app, uvicorn and Alembic |
| `apps/api/src/api/db.py` | SQLAlchemy engine (pool, pre-ping, connect timeout) and per-request session |
| `apps/api/src/api/models.py` | `tasks` table model |
| `apps/api/src/api/schemas.py` | Request and response models with validation |
| `apps/api/src/api/metrics.py` | Prometheus request counter and latency histogram |
| `apps/api/src/api/routes/health.py` | `/healthz`, `/readyz`, `/metrics` |
| `apps/api/src/api/routes/tasks.py` | Task CRUD endpoints |
| `apps/api/src/api/routes/debug.py` | CPU and memory stress endpoints, mounted only when enabled |
| `apps/api/tests/` | Unit tests (health, tasks, debug, config) with a SQLite session override |

### pre-commit

```bash
pre-commit install            # installs both the pre-commit and commit-msg hooks
pre-commit run --all-files    # run every hook against the whole repo
```

| Hook | Purpose |
| --- | --- |
| trailing-whitespace, end-of-file-fixer | Whitespace hygiene |
| check-yaml | Valid YAML (Helm `templates/` excluded) |
| check-added-large-files, check-merge-conflict | Block oversized files and conflict markers |
| detect-private-key, gitleaks | Block committed secrets |
| terraform_fmt, terraform_validate, terraform_tflint | Terraform formatting, validation and linting |
| ruff-check, ruff-format | Python linting and formatting |
| conventional-pre-commit (commit-msg) | Enforce Conventional Commit messages |

Git workflow: trunk-based, with a protected `main`, short-lived branches, Conventional Commits, and squash plus fast-forward merges. See [ADR 0009](docs/adr/0009-trunk-based-git-workflow.md).

## Cost estimate and teardown policy

Approximate on-demand prices for **us-east-1** while the full stack is running. Check the current AWS pricing pages before relying on them.

| Resource | Approx. cost |
| --- | --- |
| EKS control plane (standard support) | $0.10/h, about $73/month |
| NAT Gateway (x1) | $0.045/h plus $0.045/GB processed, about $33/month + data |
| 2 x t3.large worker nodes | $0.083/h each, about $121/month |
| Application Load Balancer | about $16/month + LCUs |
| Public IPv4 addresses (NAT + ALB) | $0.005/h each, about $11/month |
| EBS gp3 (node root volumes + Postgres PVC) | a few $/month |
| Route 53 zone, Secrets Manager, ECR, S3 state, KMS keys, CloudWatch Logs | about $3–5/month |
| **Total** | **about $265/month, roughly $8–9 per day** |

The `network` and `eks` stacks alone cost about **$0.32 per hour** (control plane, two nodes, NAT Gateway and its public IP).

> Lab shortcuts: a single NAT Gateway ([ADR 0007](docs/adr/0007-single-nat-gateway-in-lab.md)), a small node group, and in-cluster Postgres ([ADR 0002](docs/adr/0002-postgres-statefulset-first-rds-later.md)). A production setup costs noticeably more.
> Keep the cluster on an EKS version in standard support. Extended support raises the control plane price to $0.60/h.

**Teardown policy**: destroy the costly stacks at the end of **every** session, in reverse order:

```bash
terraform -chdir=infra/addons  destroy   # removes the ALB created by the controller first
make down                                # destroys eks, then network (NAT Gateway, Elastic IP)
```

`make up` creates the platform in the opposite order (`network`, then `eks`). Both targets initialise each stack with its own `backend.hcl` and ask for confirmation before every apply or destroy.

- Keep `bootstrap` (the state bucket) and the Route 53 hosted zone. They cost almost nothing, and DNS delegation is slow to redo.
- Afterwards, check the console (read-only) for leftover load balancers, EBS volumes, ENIs and Elastic IPs.

## Roadmap

- [x] **M0**: Repository, `.gitignore`, pre-commit hooks
- [x] **M1**: Project documentation and ADRs
- [x] **M2**: `bootstrap` stack: S3 state bucket (versioned, encrypted, public access blocked), see [`infra/bootstrap/`](infra/bootstrap/README.md)
- [x] **M3**: `network` stack: VPC, public/private subnets across 2 AZs, single NAT Gateway, load balancer subnet tags, see [`infra/network/`](infra/network/README.md)
- [x] **M4**: `eks` stack: EKS 1.37 cluster, managed node group (amd64, AL2023), OIDC provider for IRSA, core managed add-ons, access entries, see [`infra/eks/`](infra/eks/README.md)
- [ ] **M5**: `addons` stack: EBS CSI driver, AWS Load Balancer Controller, ExternalDNS, External Secrets Operator, metrics-server (IRSA roles)
- [ ] **M6**: `web` and `api` FastAPI apps, Dockerfiles, multi-arch images in ECR (`api` + local Compose stack done)
- [ ] **M7**: Helm charts for `web`, `api` and the `postgres` StatefulSet
- [ ] **M8**: GitLab CI: lint, test, build, scan, push, `helm upgrade --install`
- [ ] **M9**: Gateway API + Route 53 (`<app>.lab.<domain>`) + ACM TLS
- [ ] **M10**: Observability: kube-prometheus-stack, dashboards, alerts
- [ ] **M11**: Move PostgreSQL from the StatefulSet to Amazon RDS
- [ ] **M12**: Hardening: NetworkPolicies, Pod Security Admission, resource requests/limits, image scanning

## Security notes

- **No long-lived AWS credentials.** Humans use IAM Identity Center (SSO). Pods use IRSA ([ADR 0005](docs/adr/0005-irsa-for-pod-aws-access.md)). CI authenticates to AWS without static keys (method to be decided at M8).
- **Secrets** live in AWS Secrets Manager. External Secrets Operator syncs them into Kubernetes Secrets ([ADR 0004](docs/adr/0004-external-secrets-operator.md)). Secrets never go in Git, Helm values or CI logs.
- **Least privilege.** Each controller and app gets its own IAM role, scoped to its own ServiceAccount.
- **Network.** Worker nodes run in private subnets. Only the ALB is internet-facing.
- **Terraform state** sits in an encrypted, versioned S3 bucket with public access blocked. State is never committed or printed.
- **Secret scanning** runs on every commit (gitleaks, detect-private-key).
- **Public repository.** This repo is mirrored publicly, so it uses placeholders only (`<domain>`, `<account-id>`). It never contains real account IDs, emails, domains or internal URLs.
- **Tagging.** Every AWS resource is tagged `Project`, `Env`, `Owner` and `ManagedBy` (through provider `default_tags`).
