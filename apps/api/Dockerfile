# api image: build the virtualenv with Debian's Python 3.13, run it on distroless.
# Base images are pinned by tag and digest; the tag documents intent, the digest is what is pulled.
# Multi-arch (linux/amd64, linux/arm64): no architecture-specific steps below.

# ---- uv binary only -----------------------------------------------------------
FROM ghcr.io/astral-sh/uv:0.13.5@sha256:32a7bb39b496babbd997b0a39a4d66c126bdaf5661b302bf6f06abda8deca6ff AS uv

# ---- build: resolve and install dependencies into /app/.venv ------------------
# Same Debian release as the runtime image, so the venv's interpreter (/usr/bin/python3.13)
# and compiled wheels match exactly what distroless provides.
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

# Dependencies first: this layer is reused until pyproject.toml or uv.lock changes.
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    uv sync --frozen --no-dev --no-install-project

# Then the application itself, installed as a regular (non-editable) package.
COPY pyproject.toml uv.lock ./
COPY src ./src
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-editable

# ---- runtime: no shell, no package manager ------------------------------------
FROM gcr.io/distroless/python3-debian13:nonroot@sha256:64e54c4b1200da244d80181d98e86fc01d73c8101f107d5baf472152d8e119a2 AS runtime

WORKDIR /app

# Owned by root and read-only to the app user: the process cannot modify its own code.
COPY --from=build /app/.venv /app/.venv
COPY alembic.ini ./
COPY migrations ./migrations

ENV PATH="/app/.venv/bin:${PATH}" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PSYCOPG_IMPL=binary

# Numeric UID:GID (distroless "nonroot") so Kubernetes runAsNonRoot can verify it.
USER 65532:65532

EXPOSE 8000

# Exec form: python is PID 1 and receives SIGTERM directly.
# Migrations use the same image: `--entrypoint /app/.venv/bin/alembic ... upgrade head`.
ENTRYPOINT ["/app/.venv/bin/python", "-m", "api"]
