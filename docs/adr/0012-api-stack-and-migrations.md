# 0012. api stack: uv, SQLAlchemy + psycopg, Alembic as a separate step, distroless runtime

Status: Accepted, 2026-10-26

## Context

The FastAPI `api` needs a dependency workflow, a PostgreSQL driver, schema migrations and a runtime image. The same image must run under Compose and on amd64 EKS nodes ([ADR 0006](0006-amd64-nodes-multi-arch-images.md)), take config from the environment, run as several replicas and keep a small attack surface.

## Decision

- Dependencies: uv, with a committed, hashed `uv.lock`. Images install with `uv sync --frozen --no-dev`.
- Database: sync SQLAlchemy 2.0 with psycopg 3, at most 10 connections per replica. `psycopg[binary]` bundles libpq, so the runtime needs no system library.
- Schema: Alembic, run as a separate one-shot step from the same image, never at app startup. Locally it is the `migrate` Compose service; on Kubernetes a Job or Helm hook.
- Runtime: multi-stage build on `debian:trixie-slim`, running on `gcr.io/distroless/python3-debian13:nonroot`, which ships the same Python 3.13. Base images are pinned by digest, and the process runs as UID 65532.
- Tests: pytest with the database session overridden by in-memory SQLite.

## Consequences

Builds are reproducible and dependency changes show up in review. The image is 45 MB compressed against 449 MB for a single-stage `python:3.13` build, and it runs non-root on a read-only filesystem. One migration per release keeps rollouts safe, but migrations must stay compatible with the previous version. libpq and OpenSSL fixes come from bumping `psycopg-binary`, so image scanning must cover Python packages. Distroless has no shell, so debugging uses `kubectl debug`. SQLite tests miss PostgreSQL-specific behaviour, which Compose and later CI integration tests cover.
