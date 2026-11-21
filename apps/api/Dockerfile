# Builds the venv with Debian's Python 3.13 and runs it on distroless. Base images are pinned by
# digest; the tag is for readers. No architecture-specific steps, so it builds for amd64 and arm64.

FROM ghcr.io/astral-sh/uv:0.13.5@sha256:32a7bb39b496babbd997b0a39a4d66c126bdaf5661b302bf6f06abda8deca6ff AS uv

# Same Debian release as the runtime image, so the interpreter and compiled wheels match.
FROM debian:trixie-20261020-slim@sha256:62bd423aeee912639ca8ee681c2b762cb3e25137e0a92b20be455898a9f034ad AS build

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=uv /uv /usr/local/bin/uv

ENV UV_PYTHON=/usr/bin/python3 \
    UV_PYTHON_DOWNLOADS=never \
    UV_PROJECT_ENVIRONMENT=/app/.venv \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

WORKDIR /app

# Dependencies first, so this layer is cached until the lock file changes.
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    uv sync --frozen --no-dev --no-install-project

COPY pyproject.toml uv.lock ./
COPY src ./src
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-editable

FROM gcr.io/distroless/python3-debian13:nonroot@sha256:6c4cb3bfa4b555429dd19541796a6ba6b30c84675b460bd0bd5072f7d5bdae71 AS runtime

WORKDIR /app

# Owned by root, so the app cannot modify its own code.
COPY --from=build /app/.venv /app/.venv
COPY alembic.ini ./
COPY migrations ./migrations

ENV PATH="/app/.venv/bin:${PATH}" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PSYCOPG_IMPL=binary

# Numeric, so Kubernetes runAsNonRoot can verify it.
USER 65532:65532

EXPOSE 8000

# Exec form, so python is PID 1 and receives SIGTERM. Migrations override the entrypoint with alembic.
ENTRYPOINT ["/app/.venv/bin/python", "-m", "api"]
