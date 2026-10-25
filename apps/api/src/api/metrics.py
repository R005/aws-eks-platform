"""Prometheus metrics. The default registry also exports process_* and python_* metrics."""

from prometheus_client import Counter, Histogram

# `route` is the path template (/tasks/{task_id}), never the raw path, to bound label cardinality.
HTTP_REQUESTS = Counter(
    "http_requests_total", "HTTP requests handled", ["method", "route", "status"]
)
HTTP_LATENCY = Histogram(
    "http_request_duration_seconds", "HTTP request latency in seconds", ["method", "route"]
)
