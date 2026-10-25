# api: operational contract

What the platform can rely on when running the `api` image. Design decisions: [ADR 0012](../../docs/adr/0012-api-stack-and-migrations.md).

## Runtime

| Property | Value |
| --- | --- |
| Image | `apps/api/Dockerfile`; distroless, multi-arch (`linux/amd64`, `linux/arm64`) |
| Process | one uvicorn process (no workers), PID 1; scale with replicas |
| Port | `8000/TCP`, plain HTTP (TLS ends at the load balancer) |
| User | UID:GID `65532:65532`; needs no Linux capabilities |
| Filesystem | works with a read-only root filesystem; provide a writable `/tmp` (tmpfs / `emptyDir`) |
| State | stateless; all data lives in PostgreSQL |

## Configuration (environment variables only)

| Variable | Required | Default | Secret | Purpose |
| --- | --- | --- | --- | --- |
| `DB_HOST` | yes | none | no | PostgreSQL host |
| `DB_PORT` | no | `5432` | no | PostgreSQL port |
| `DB_NAME` | yes | none | no | Database name |
| `DB_USER` | yes | none | no | Database user |
| `DB_PASSWORD` | yes | none | **yes** | Database password. Inject from a Secret (External Secrets on Kubernetes, `.env` locally). It is never logged |
| `DB_CONNECT_TIMEOUT` | no | `3` | no | Seconds to wait for a new database connection |
| `LOG_LEVEL` | no | `INFO` | no | `DEBUG`, `INFO`, `WARNING`, `ERROR` |
| `ENABLE_DEBUG_ENDPOINTS` | no | `false` | no | `true` mounts `/debug/load/*`. Keep it off outside drills |

A missing or invalid variable makes the process exit non-zero at startup with a message that names the variables but never their values (`invalid configuration: DB_HOST: Field required; …`).

## Endpoints

| Path | Use | Behaviour |
| --- | --- | --- |
| `GET /healthz` | liveness | Always `200 {"status":"ok"}` while the process can serve. No dependencies, so a database outage never triggers restarts |
| `GET /readyz` | readiness | `200` when `SELECT 1` succeeds, `503 {"status":"unavailable"}` otherwise. Takes the replica out of rotation without restarting it |
| `GET /metrics` | Prometheus scrape | Prometheus text format, see [Metrics](#metrics) |
| `/tasks`, `/tasks/{id}` | application API | CRUD; the OpenAPI document is at `/openapi.json` |
| `POST /debug/load/cpu`, `/debug/load/memory` | stress drills | Only when `ENABLE_DEBUG_ENDPOINTS=true`, otherwise `404`. See [Debug drills](#debug-drills) |

## Database migrations

- Command (same image, different entrypoint): `/app/.venv/bin/alembic upgrade head`
- Run it **once per release, before the new version starts**. Never run it from every replica. Locally it's the `migrate` Compose service; on Kubernetes, a Job / Helm pre-upgrade hook.
- It's idempotent: it applies only revisions newer than the one recorded in `alembic_version`, and exits `0` when there's nothing to do.
- It reads the same `DB_*` variables as the api and logs JSON to stdout.
- Migrations must stay compatible with the previous app version (expand, then contract), because old replicas keep serving during a rollout.

## Startup and shutdown

- **Startup:** about 0.4 s from container start to accepting requests (measured locally). It doesn't wait for the database; `/readyz` reports `503` until the database answers.
- **SIGTERM:** uvicorn stops accepting new connections and lets in-flight requests finish for up to **20 s**. It then runs shutdown (closes the database pool), logs `api shutting down, closing database pool`, and exits `0`. Measured locally: about 0.4 s when idle.
- **Grace period:** give the container at least 25 s between SIGTERM and SIGKILL. Kubernetes' default `terminationGracePeriodSeconds: 30` and the Compose `stop_grace_period: 30s` both fit.
- Kubernetes removes a terminating pod from Service endpoints asynchronously. Requests can still arrive for a moment after SIGTERM, which is usually handled with a short `preStop` delay in the chart.

## Logs

- One JSON object per line on **stdout**. Nothing is written to files.
- Fields: `ts` (UTC, ISO 8601, ms), `level`, `logger`, `msg`, plus context fields.
- Access log: one line per request with `method`, `path`, `status`, `duration_ms` (logger `api`, `msg: "request"`). Requests to `/healthz`, `/readyz` and `/metrics` are logged at `DEBUG` only.
- Errors include a formatted traceback in `exc`. Secrets and request bodies are never logged.

```json
{"ts": "2026-10-26T09:15:02.118+00:00", "level": "INFO", "logger": "api", "msg": "request", "method": "POST", "path": "/tasks", "status": 201, "duration_ms": 4.71}
```

## Metrics

| Metric | Type | Labels |
| --- | --- | --- |
| `http_requests_total` | counter | `method`, `route`, `status` |
| `http_request_duration_seconds` | histogram | `method`, `route` |
| `process_*` (CPU, RSS, open FDs, start time), `python_*` (GC, info) | standard | none |

`route` is the path template (`/tasks/{task_id}`), never the raw path, so label cardinality stays bounded. Requests that match no route are labelled `unmatched`. There's one process per container, so no multiprocess collector is needed.

## Database connections

- Pool: 5 connections, plus up to 5 overflow, so **at most 10 connections per replica**. Size Postgres `max_connections` (default 100) against `replicas × 10` plus migrations and admin sessions.
- Dead connections are detected before use (`pool_pre_ping`), so the api recovers after a database restart without restarting itself.

## Resource usage (measured)

Measured on 2026-10-26 under Docker Compose. Environment: Apple Silicon, arm64, Docker Desktop, a handful of rows, client on the same host. Treat these as relative figures and re-measure on the EKS node type (amd64) before setting final requests and limits.

| Scenario | CPU | Memory (container) | Notes |
| --- | --- | --- | --- |
| Idle | ~0.2% (spikes to ~7% when the Compose healthcheck runs) | ~65 MiB | 2 PIDs |
| Startup | short spike | ~65 MiB | ~0.4 s to ready |
| Load: `GET /tasks`, 20 concurrent clients for 15 s | ~1.5 cores | ~70 MiB | ~1,070 req/s, p50 18 ms, p95 33 ms, p99 45 ms, 0 errors; up to ~30 threads |
| Postgres during that load | ~0.1 core | ~43 MiB | 19 processes (≤ 10 api connections) |
| CPU drill: `workers=2` | ~2 cores (1 per worker) | ~129 MiB | each worker is a separate Python process (~30 MiB) |
| Memory drill: `mb=200` | low | ~275 MiB | memory rises by about the requested amount for `seconds`, then is released |

Under load the CPU used depends on traffic. A single replica can use more than one core (database I/O releases the GIL), so a CPU limit at or below 1 core throttles throughput.

## Debug drills

Enabled only with `ENABLE_DEBUG_ENDPOINTS=true`. Both return `202` immediately and run in the background.

| Endpoint | Parameters (caps) | Effect |
| --- | --- | --- |
| `POST /debug/load/cpu` | `seconds` 1–120 (30), `workers` 1–8 (1) | Each worker is a child process spinning one core. Probes stay responsive. Use it to exercise HPA scale-out |
| `POST /debug/load/memory` | `mb` 1–1024 (256), `seconds` 1–120 (30) | Allocates and touches `mb` MiB inside the api process. Use it to exercise memory alerts or an OOMKill above the limit |
