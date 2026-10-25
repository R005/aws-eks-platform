"""CPU and memory stress endpoints for autoscaling and OOM drills.

Mounted only when ENABLE_DEBUG_ENDPOINTS=true; otherwise these paths return 404.
"""

import logging
import multiprocessing
import threading
import time
from typing import Annotated

from fastapi import APIRouter, Query, status

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/debug/load", tags=["debug"])

MAX_SECONDS = 120
MAX_MB = 1024
MAX_WORKERS = 8
PAGE = 4096


def _burn_cpu(seconds: int) -> None:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        pass


def _hold_memory(mb: int, seconds: int) -> None:
    block = bytearray(mb * 1024 * 1024)
    block[::PAGE] = b"\x01" * len(range(0, len(block), PAGE))  # touch every page so RSS grows
    time.sleep(seconds)


def start_cpu_burn(seconds: int, workers: int) -> None:
    multiprocessing.active_children()  # reap finished burners
    # Separate processes keep the event loop (and the probes) responsive, and still count
    # against the container's CPU cgroup. "spawn" avoids forking a multi-threaded server.
    ctx = multiprocessing.get_context("spawn")
    for _ in range(workers):
        ctx.Process(target=_burn_cpu, args=(seconds,), daemon=True).start()


def start_memory_hold(mb: int, seconds: int) -> None:
    # Held in-process on purpose, so the api container's own memory usage rises.
    threading.Thread(target=_hold_memory, args=(mb, seconds), daemon=True).start()


@router.post("/cpu", status_code=status.HTTP_202_ACCEPTED)
def cpu_load(
    seconds: Annotated[int, Query(ge=1, le=MAX_SECONDS)] = 30,
    workers: Annotated[int, Query(ge=1, le=MAX_WORKERS)] = 1,
) -> dict:
    logger.warning("cpu load drill started", extra={"seconds": seconds, "workers": workers})
    start_cpu_burn(seconds, workers)
    return {"load": "cpu", "seconds": seconds, "workers": workers}


@router.post("/memory", status_code=status.HTTP_202_ACCEPTED)
def memory_load(
    mb: Annotated[int, Query(ge=1, le=MAX_MB)] = 256,
    seconds: Annotated[int, Query(ge=1, le=MAX_SECONDS)] = 30,
) -> dict:
    logger.warning("memory load drill started", extra={"mb": mb, "seconds": seconds})
    start_memory_hold(mb, seconds)
    return {"load": "memory", "mb": mb, "seconds": seconds}
