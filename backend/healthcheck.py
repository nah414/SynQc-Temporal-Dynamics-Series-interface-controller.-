#!/usr/bin/env python3
"""
Simple healthcheck script for Docker containers.
Returns exit code 0 if healthy, 1 otherwise.
"""
import sys
import urllib.request
import urllib.error

def check_health(url="http://127.0.0.1:8001/health"):
    """Check if the health endpoint returns 200 OK."""
    try:
        with urllib.request.urlopen(url, timeout=3) as response:
            if response.status == 200:
                return 0
            else:
                print(f"Health check failed: HTTP {response.status}", file=sys.stderr)
                return 1
    except urllib.error.URLError as e:
        print(f"Health check failed: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"Health check failed: {e}", file=sys.stderr)
        return 1

if __name__ == "__main__":
    sys.exit(check_health())
