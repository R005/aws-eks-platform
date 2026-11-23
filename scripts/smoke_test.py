#!/usr/bin/env python3
import json
import os
import sys
import time
import urllib.error
import urllib.request

BASE_URL = f"https://{os.environ['APP_HOST']}"


def call(method, path, body=None):
    data = json.dumps(body).encode() if body else None
    headers = {"Content-Type": "application/json"}
    request = urllib.request.Request(BASE_URL + path, data, headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, b""
    except OSError as error:
        return error, b""


def check(method, path, expected, body=None, attempts=1):
    for attempt in range(attempts):
        if attempt:
            time.sleep(10)
        status, content = call(method, path, body)
        if status == expected:
            print(f"PASS {method} {path} -> {status}")
            return content
    sys.exit(f"FAIL {method} {path} -> {status}, expected {expected}")


# The ALB and its DNS record take a few minutes on the first deploy.
check("GET", "/readyz", 200, attempts=30)
check("GET", "/tasks", 200)
task = json.loads(check("POST", "/tasks", 201, {"title": "smoke test"}))
check("DELETE", f"/tasks/{task['id']}", 204)
