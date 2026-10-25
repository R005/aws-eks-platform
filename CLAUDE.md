# CLAUDE.md: aws-eks-platform

Project-specific facts and rules for Claude Code.

## Project facts

| Key | Value |
| --- | --- |
| Project name | `aws-eks-platform` |
| Resource name prefix | `eks-platform` (for example `eks-platform-dev-vpc`) |
| Environment | `dev` |
| AWS profile | `lab-dev`, set by direnv (`.envrc`, gitignored). Referenced by name only, never in provider blocks. |
| Region | `us-east-1`, passed as a variable or through the environment, never hardcoded in provider blocks |
| DNS zone | `lab.<domain>` (placeholder) |
| App hostnames | `<app>.lab.<domain>` |
| Required tags | `Project`, `Env`, `Owner`, `ManagedBy` (through provider `default_tags`) |

App: Python 3-tier task tracker: FastAPI `web` → FastAPI `api` → PostgreSQL (StatefulSet first, RDS later).
Decisions live in `docs/adr/`. Read the relevant ADR before changing an area, and add a new ADR for any significant new decision.

## Git workflow (ADR 0009)

- `main` is protected. Changes land only through a merge request with a green pipeline.
- Use short-lived branches off `main`, named `<type>/<short-description>`.
- Use Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`, `ci:`, `refactor:`, `test:` …). The commit-msg hook enforces this.
- Merge method: squash, fast-forward only. Rebase on `main` before merging. No merge commits.
- Claude never commits, pushes or opens an MR unless explicitly asked.

## Public repository rule

This repo is mirrored to a **public** GitHub repo. Never write sensitive data into any tracked file, commit message or MR description:

- Use placeholders only: `<domain>`, `<account-id>`, `<region>`, `<app>`.
- Never include real AWS account IDs, ARNs containing account IDs, emails, real domains, internal URLs, IP allowlists, Terraform state or plan output, or kubeconfig content.
- When showing command output that contains such values, redact it before it goes into docs.

## Repo layout (planned)

```text
apps/{web,api}/                                  FastAPI services + Dockerfiles
helm/{web,api,postgres}/                         Helm charts (+ values-dev.yaml)
terraform/modules/                               reusable modules
terraform/stacks/{bootstrap,network,eks,addons}/ one root module + state per layer
docs/adr/                                        Architecture Decision Records
.gitlab-ci.yml                                   CI/CD pipeline
```

Terraform stacks are applied in the order `bootstrap → network → eks → addons` and destroyed in reverse (keep `bootstrap` and the Route 53 zone).
