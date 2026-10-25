# 0012. api stack: uv, SQLAlchemy + psycopg, Alembic as a separate step, distroless runtime

- **Status:** Accepted
- **Date:** 2026-10-26

## Context
The `api` service (FastAPI) needs a dependency workflow, a PostgreSQL driver, a way to create and evolve the schema, and a runtime image. The same image must run under Docker Compose locally and on amd64 EKS nodes ([ADR 0006](0006-amd64-nodes-multi-arch-images.md)), with config and secrets from the environment ([ADR 0004](0004-external-secrets-operator.md)), several replicas, and a small attack surface.

## Decision
- **Dependencies: uv.** `pyproject.toml` plus a committed `uv.lock` with hashes. Images install with `uv sync --frozen --no-dev`, so builds never re-resolve versions.
- **Database access: SQLAlchemy 2.0 (sync) + psycopg 3.** FastAPI runs sync handlers in its threadpool, which is enough at this scale. The connection pool is capped at 10 connections per replica.
- **libpq: `psycopg[binary]`.** Its manylinux wheels bundle libpq and OpenSSL, so the runtime image needs no system libpq. `PSYCOPG_IMPL=binary` makes a missing binary fail at startup.
- **Schema: Alembic migrations, run as a separate one-shot step** from the same image (`alembic upgrade head`). Locally it's the `migrate` Compose service, which the api waits on (`service_completed_successfully`). On Kubernetes it becomes a Job / Helm pre-upgrade hook. The api never migrates at startup.
- **Runtime image: multi-stage, distroless.** The builder is `debian:trixie-slim` with Debian's `python3` (3.13). The runtime is `gcr.io/distroless/python3-debian13:nonroot`, which ships the same interpreter, so the copied virtualenv runs unchanged. Every base image is pinned by tag and digest. The process runs as numeric UID 65532 with no shell or package manager in the image.
- **Tests: pytest + FastAPI TestClient**, with the database session overridden by in-memory SQLite. Unit tests need neither Postgres nor Docker.

## Consequences
- Builds are reproducible, and dependency changes show up as `uv.lock` diffs in review.
- The runtime image is 45 MB compressed (152 MB unpacked), against 449 MB (1.26 GB) for a single-stage `python:3.13` build. It runs as non-root and works with a read-only root filesystem.
- Rolling updates are safe with several replicas: there's one migration per release, not one per pod. Migrations must stay backward-compatible with the previous app version (expand, then contract), because old pods keep serving while new ones roll out.
- libpq and OpenSSL fixes arrive by bumping `psycopg-binary` in `uv.lock`, not by OS updates. Image scanning (M12) has to cover Python packages.
- The Python patch version follows Debian (3.13.5 at the time of writing) rather than the latest upstream 3.13.x. Debian backports security fixes.
- Distroless has no shell. Debugging uses `kubectl debug` ephemeral containers, and the Compose healthcheck uses the image's own Python instead of curl.
- SQLite in unit tests does not catch PostgreSQL-specific behaviour. That's covered by running against real Postgres (Compose now, CI integration tests later).

## Alternatives considered
- **pip-tools / Poetry:** both work. pip-tools is more manual. Poetry is slower and awkward in multi-stage builds.
- **SQLAlchemy async + asyncpg:** better under very high concurrency, but async sessions and tests are more complex than this service needs.
- **Raw SQL with psycopg only:** transparent, but more hand-written code and no model-driven migrations.
- **System libpq copied into distroless:** fragile, because `libpq.so.5` and its transitive libraries (libssl, libgssapi, libldap…) all have to be copied by hand.
- **Migrations at app startup:** replicas race each other on deploy. **`create_all()`:** no versioning, and it can't alter existing tables.
- **`python:3.13-slim` runtime:** official upstream Python, but it still has a shell and apt. **Chainguard:** minimal, but the free tier offers only `:latest`.
