# api operations

What the platform can rely on when running the `api` image. Design decisions are in [ADR 0012](../../docs/adr/0012-api-stack-and-migrations.md).

## Runtime

One uvicorn process on port 8000, plain HTTP, with TLS ending at the load balancer. Scale with replicas, not workers. The image is distroless and runs as UID:GID `65532:65532` with no capabilities. It works with a read-only root filesystem if `/tmp` is writable. The api is stateless; all data lives in PostgreSQL.

## Configuration

| Variable | Default | Notes |
| --- | --- | --- |
| `DB_HOST` | required | |
| `DB_PORT` | `5432` | |
| `DB_NAME` | required | |
| `DB_USER` | required | |
| `DB_PASSWORD` | required | Secret. Inject from a Kubernetes Secret or `.env`; never logged |
| `DB_CONNECT_TIMEOUT` | `3` | Seconds |
| `LOG_LEVEL` | `INFO` | |
| `ENABLE_DEBUG_ENDPOINTS` | `false` | Mounts `/debug/load/*`. Keep it off outside drills |

A missing or invalid variable stops the process at startup with a message that names the variable but never its value.

## Endpoints

| Path | Behaviour |
| --- | --- |
| `GET /healthz` | Liveness. Always `200` while the process can serve, with no dependencies, so a database outage never restarts the pod |
| `GET /readyz` | Readiness. `200` when `SELECT 1` succeeds, otherwise `503` |
| `GET /metrics` | Prometheus text format |
| `/tasks`, `/tasks/{id}` | CRUD. OpenAPI at `/openapi.json` |
| `POST /debug/load/cpu`, `/debug/load/memory` | Drills, only when enabled, otherwise `404` |

## Migrations

Run `/app/.venv/bin/alembic upgrade head` from the same image, once per release and before the new version starts, never from every replica. It is idempotent and reads the same `DB_*` variables. Old replicas keep serving during a rollout, so each migration must work with the previous app version (expand, then contract).

## Startup and shutdown

The api is ready in about 0.4 s and does not wait for the database; `/readyz` returns `503` until it answers. On SIGTERM uvicorn stops accepting connections, drains in-flight requests for up to 20 s, closes the database pool and exits 0. Allow at least 25 s between SIGTERM and SIGKILL.

## Logs and metrics

One JSON object per line on stdout, with `ts`, `level`, `logger`, `msg` and context fields. Each request logs `method`, `path`, `status` and `duration_ms`; probes and scrapes log at `DEBUG`. Request bodies and secrets are never logged.

```json
{"ts": "2026-10-26T09:15:02.118+00:00", "level": "INFO", "logger": "api", "msg": "request", "method": "POST", "path": "/tasks", "status": 201, "duration_ms": 4.71}
```

Metrics are `http_requests_total` (`method`, `route`, `status`) and `http_request_duration_seconds` (`method`, `route`), plus the standard `process_*` and `python_*` series. `route` is the path template, never the raw path, so cardinality stays bounded; unmatched requests use `unmatched`.

## Database connections

Each replica uses a pool of 5 plus 5 overflow, so at most 10 connections. Size Postgres `max_connections` for `replicas x 10` plus migrations and admin sessions. `pool_pre_ping` drops dead connections, so the api recovers from a database restart by itself.

## Resource usage

Measured on 2026-10-26 under Compose on Apple Silicon. Re-measure on the amd64 nodes before relying on these numbers.

| Scenario | CPU | Memory |
| --- | --- | --- |
| Idle | about 0.2% | about 65 MiB |
| `GET /tasks`, 20 concurrent clients | about 1.5 cores, ~1,070 req/s, p99 45 ms | about 70 MiB |
| CPU drill, `workers=2` | about 2 cores | about 129 MiB |
| Memory drill, `mb=200` | low | about 275 MiB |

One replica can use more than one core because database I/O releases the GIL, so a CPU limit of 1 core or less throttles it.

## Debug drills

Both endpoints take query parameters, return `202` immediately and run in the background.

| Endpoint | Parameters, range (default) | Effect |
| --- | --- | --- |
| `POST /debug/load/cpu` | `seconds` 1-120 (30), `workers` 1-8 (1) | One child process per worker spins a core; probes stay responsive |
| `POST /debug/load/memory` | `mb` 1-1024 (256), `seconds` 1-120 (30) | Allocates `mb` MiB inside the api process |

```bash
curl -X POST 'localhost:8000/debug/load/memory?mb=100&seconds=60'
```

With the chart's 256Mi limit, the default `mb=256` gets the pod OOMKilled.
