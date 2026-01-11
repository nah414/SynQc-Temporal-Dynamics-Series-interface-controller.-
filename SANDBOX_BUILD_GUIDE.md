# SynQc TDS Hybrid Controller — Sandbox Build Guide (Docker + Prometheus + Grafana)

**Audience:** future-you (and any teammate) who wants to reproduce a clean, observable sandbox build of the SynQc Temporal Dynamics Series (TDS) Hybrid Controller.

**What this document is:** a practical, reproducible build + troubleshooting log distilled from our build session. It includes:
- what we built and why
- exact commands (Windows + Git Bash friendly)
- what went wrong (real symptoms)
- how we diagnosed it
- how we fixed it
- verification checks that prove the stack is actually healthy
- “rules of engagement” we followed so we don’t waste time next run

---

## Goals

1. Run the full local sandbox stack in Docker (API + Worker + Redis + Web UI + Prometheus).
2. Make Prometheus show **healthy scrape targets** (API metrics at minimum; Worker metrics optional but supported).
3. Confirm the system processes a run end-to-end (queue -> worker -> result).
4. Hook Prometheus into Grafana for dashboards/alerting (local Grafana or Grafana Cloud).

---

## Architecture (what runs where)

### Docker services (compose stack)
Typical services we ran:
- **api** (FastAPI/Uvicorn): serves API endpoints on `:8001` and exposes Prometheus metrics on `:9000`
- **worker**: consumes queued runs and executes them (and optionally exposes worker metrics on `:9001`)
- **redis**: queue + job state store
- **prometheus**: scrapes metrics from api/worker and serves UI/API on `:9090`
- **web**: front-end UI on `:8080`
- **shor** (optional addon): demo service on `:8002`

### Ports (host -> container)
- Web UI: `http://127.0.0.1:8080`
- API: `http://127.0.0.1:8001`
- Prometheus: `http://127.0.0.1:9090`
- Redis (host-only bind): `127.0.0.1:6379`
- Worker metrics (optional): `http://worker:9001/metrics` inside docker network

Grafana (local) if you run it:
- `http://127.0.0.1:3000`

---

## Repo & environment assumptions

- Windows + Docker Desktop
- Git Bash (MINGW64) at:
  `C:\_work\synqc-temporal-dynamics-series-hybrid-controller`
- Python available locally as `py -3`
- Docker Compose v2 (`docker compose ...`)

---

## Quick start (clean, reproducible path)

### 0) From Git Bash: enter repo root

```bash
cd /c/_work/synqc-temporal-dynamics-series-hybrid-controller || exit 1
```

### 1) Start stack

```bash
docker compose up -d --build
docker compose ps
```

### 2) Confirm API health

```bash
curl -sS http://127.0.0.1:8001/health | py -3 -m json.tool
```

### 3) Confirm Prometheus targets are UP

```bash
py -3 - <<'PY'
import json, urllib.request
j = json.loads(urllib.request.urlopen("http://127.0.0.1:9090/api/v1/targets").read())
for t in j["data"]["activeTargets"]:
    labels = t.get("labels", {})
    print("job=", labels.get("job"), "| health=", t.get("health"), "| url=", t.get("scrapeUrl"), "| err=", t.get("lastError",""))
PY
```

You want at least:
- `synqc-api` = `up` (scraping `http://api:9000/metrics`)

If you also scrape worker metrics:
- `synqc-worker` = `up` (scraping `http://worker:9001/metrics`)

### 4) Submit a run and verify it completes

```bash
curl -sS -X POST "http://127.0.0.1:8001/runs" \
  -H "Content-Type: application/json" \
  -d '{"preset":"hello_quantum_sim","hardware_target":"sim_local","mode":"explore","shot_budget":64,"notes":"sandbox smoke test"}' \
  -w "\nHTTP_CODE=%{http_code}\n"
```

Then (paste the returned id into RUN_ID):

```bash
RUN_ID="PASTE_ID_HERE"
curl -sS "http://127.0.0.1:8001/runs/$RUN_ID" | py -3 -m json.tool
```

Status should move from `queued` -> `succeeded` quickly for `sim_local`.

---

## Prometheus configuration

Prometheus config file is stored at:

- `docker/prometheus.yml` (host)
- mounted read-only into container at `/etc/prometheus/prometheus.yml`

Example config we used:

```yaml
global:
  scrape_interval: 5s
  evaluation_interval: 5s

scrape_configs:
  - job_name: "synqc-api"
    metrics_path: /metrics
    static_configs:
      - targets: ["api:9000"]

  - job_name: "synqc-worker"
    metrics_path: /metrics
    static_configs:
      - targets: ["worker:9001"]
```

### Git Bash path-conversion gotcha (Windows)
When running `docker compose exec` in Git Bash, paths can be rewritten incorrectly. If you see weird output like:

> can't open 'C:/Program Files/Git/etc/prometheus/prometheus.yml'

Use:

```bash
MSYS_NO_PATHCONV=1 docker compose exec prometheus sh -lc 'cat /etc/prometheus/prometheus.yml'
```

This forces Git Bash to stop “helpfully” rewriting paths.

---

## What went wrong (and how we fixed it)

This is the heart of the guide: symptoms -> diagnosis -> root cause -> fix -> verification.

### Issue 1 — Prometheus target DOWN: `connect: connection refused`

**Symptom**
Prometheus target shows:

- `synqc-api down http://api:9000/metrics ... connect: connection refused`

Inside the API container, tests looked like:

- connect to `127.0.0.1:9000` succeeds
- connect to container IP (e.g. `172.24.x.y:9000`) fails

**Root cause**
Metrics server bound to `127.0.0.1` inside the container. That means:
- it works from inside the container only
- it does NOT accept connections from other containers (Prometheus scrapes via `api:9000` -> container IP)

**Fix**
Bind metrics server to `0.0.0.0` (all interfaces) inside the container.

How we verified configuration from inside the API container:

```bash
docker compose exec api python -c "import os, socket; from synqc_backend import settings as m; s=m.settings; ip=socket.gethostbyname(socket.gethostname());
print('metrics_bind_address =', getattr(s,'metrics_bind_address',None));
print('SYNQC_METRICS_BIND_ADDRESS env =', os.environ.get('SYNQC_METRICS_BIND_ADDRESS'));
print('container_ip =', ip);"
```

✅ Required end state:
- `metrics_bind_address = 0.0.0.0`

**Where the change should live**
Preferred: **docker-compose.yml** under the `api:` service environment (so it’s reproducible).

If you only want it local, use a local override file **but do not commit it** (see rules below).

**Verification**
- Prometheus `/api/v1/targets` shows `synqc-api health=up`
- `curl http://127.0.0.1:9090` UI shows target green

---

### Issue 2 — Redis health OK, but `synqc_redis_connected` metric was `0`

**Symptom**
API `/health` reported Redis OK, but Prometheus metric:

- `synqc_redis_connected{backend="redis"} 0`

**Root cause**
Metrics exporter was checking one specific key (`redis_connected`) in a health summary,
but the health payload used a different key (`redis_ok`) / `ok` / `connected` depending on component.

**Fix**
Update the metric collector logic to treat **any of these keys** as truthy:
- `redis_connected`
- `redis_ok`
- `ok`
- `connected`

✅ Verification:
- `synqc_redis_connected` becomes `1` in Prometheus query UI
- API `/health` still shows Redis ok

---

### Issue 3 — Runs stuck queued forever (worker wasn’t consuming the correct queue)

**Symptom**
- API returns `202 queued`
- `/runs/{id}` stays `queued`
- Prometheus shows queued count rising
- Redis `synqc:q:*` keys were empty (no list growth)

But Redis had keys like:
- `synqc:runq:pending`
- `synqc:runq:job:<id>`

**Diagnosis command**
```bash
docker compose exec redis redis-cli TYPE synqc:runq:pending
docker compose exec redis redis-cli LLEN synqc:runq:pending
docker compose exec redis redis-cli LRANGE synqc:runq:pending 0 20
```

**Root cause**
We had *two different queue implementations* in play:

1) A simple list queue (`synqc:q:<queue_name>`) consumed by `synqc_backend.worker_service`
2) A run queue (`synqc:runq:pending`) consumed by `synqc_backend.worker`

The API was enqueueing into the **run queue** (`synqc:runq:pending`), so a worker running
`worker_service` would never see those jobs.

**Fix**
Run the correct worker entrypoint that matches the API queue:
- Use `python -m synqc_backend.worker`

**Verification**
- `synqc:runq:pending` drains to 0
- worker logs show `"Run succeeded"`
- `/runs/{id}` becomes `succeeded`

---

### Issue 4 — Worker metrics endpoint wasn’t reachable / wasn’t started

**Symptom**
Prometheus target for worker was down:
- `dial tcp ...:9001 connect: connection refused`

**Root cause**
Worker didn’t expose a metrics HTTP server by default (or it was bound wrong / not enabled).

**Fix**
Enable and bind the worker metrics endpoint:
- `SYNQC_METRICS_WORKER_ENDPOINT_ENABLED=true`
- `SYNQC_METRICS_WORKER_BIND_ADDRESS=0.0.0.0`
- `SYNQC_METRICS_WORKER_PORT=9001`

**Verification**
From inside the worker container:

```bash
docker compose exec worker python -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:9001/metrics',timeout=3).status)"
```

Should print `200`.

Prometheus targets should show:
- `synqc-worker up http://worker:9001/metrics`

**Important note**
We observed worker metrics endpoint exposed mostly default python/process metrics; `synqc_*`
series were primarily exported by the API metrics exporter. That’s OK for the MVP if your goal
is “is the system alive + are runs flowing.”

---

### Issue 5 — “Address already in use” when starting worker metrics

**Symptom**
Worker logs show `OSError: [Errno 98] Address already in use` when trying to bind to `:9001`.

**Root cause**
Something in the process already bound the port (duplicate start, or two metric servers
trying to use the same port).

**Fix**
Pick ONE mechanism per process:
- either only start the worker endpoint once
- or change the worker metrics port so it does not collide

**Verification**
- worker stays up
- `curl http://worker:9001/metrics` succeeds
- Prometheus target becomes `up`

---

## Sanity checks & smoke tests (copy/paste)

### A) Prometheus target status
```bash
py -3 - <<'PY'
import json, urllib.request
j = json.loads(urllib.request.urlopen("http://127.0.0.1:9090/api/v1/targets").read())
want = {"synqc-api","synqc-worker"}
for t in j["data"]["activeTargets"]:
    labels = t.get("labels", {})
    job = labels.get("job")
    if job in want:
        print(job, t.get("health"), t.get("scrapeUrl"), t.get("lastError",""))
PY
```

### B) Quick Prometheus queries
```bash
py -3 - <<'PY'
import json, urllib.parse, urllib.request
PROM = "http://127.0.0.1:9090/api/v1/query?query="
def q(expr: str):
    url = PROM + urllib.parse.quote(expr, safe="")
    j = json.loads(urllib.request.urlopen(url).read())
    res = j["data"]["result"]
    total = sum(float(r["value"][1]) for r in res) if res else 0.0
    print(expr, "=>", total)

for e in [
  "synqc_redis_connected",
  "synqc_queue_jobs_total",
  "synqc_queue_jobs_queued",
  "synqc_queue_jobs_running",
  "synqc_queue_jobs_succeeded",
  "synqc_queue_jobs_failed",
  "synqc_metrics_collection_errors_total",
]:
    q(e)
PY
```

### C) Redis queue inspection (run queue)
```bash
docker compose exec redis redis-cli LLEN synqc:runq:pending
docker compose exec redis redis-cli LRANGE synqc:runq:pending 0 20
```

---

## Grafana (local) setup steps

You can use **Grafana Cloud** *or* **local Grafana**. For a local sandbox, local Grafana is simpler.

### Local Grafana prerequisites
You should see it listening on port 3000:
```bash
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}" | grep -E "(:3000->|127\.0\.0\.1:3000|0\.0\.0\.0:3000)"
```

Health endpoint:
```bash
curl -sS http://127.0.0.1:3000/api/health
```

### Add Prometheus as a data source (UI steps)
1. Open: `http://127.0.0.1:3000`
2. Log in (admin/admin if default; or whatever you set)
3. Left sidebar → **Connections** → **Data sources**
4. Click **Add data source**
5. Choose **Prometheus**
6. In **Prometheus server URL**, use one of:
   - If Grafana is in the **same docker network**: `http://prometheus:9090`
   - If Grafana is NOT in the compose network: `http://host.docker.internal:9090`
   - As a fallback on Windows: `http://127.0.0.1:9090` (works when Grafana can reach host loopback; depends on container networking)
7. Click **Save & test** → it should say success.

### Suggested first panels (queries)
- `synqc_redis_connected`
- `synqc_queue_jobs_succeeded`
- `synqc_queue_jobs_failed`
- `rate(synqc_metrics_collection_errors_total[5m])`

---

## Rules of engagement (so we don’t waste hours next time)

These are the “do this every time” habits that prevented confusion and circular debugging.

1. **Never trust “it should work” — verify with direct network tests**
   - inside container: connect to `127.0.0.1` and to container IP
   - in Prometheus: `/api/v1/targets` is truth

2. **Be explicit about queue implementation**
   - check Redis keys: `KEYS synqc:*`
   - confirm which worker module is running (`/proc/1/cmdline`)

3. **Treat `docker-compose.override.yml` as a local-only tool**
   - Compose merges it automatically if present
   - Accidentally leaving it around causes “works on my machine” chaos
   - Recommendation: add to `.gitignore`

4. **Windows Git Bash: use `MSYS_NO_PATHCONV=1` for docker exec commands touching paths**
   - avoids path rewrite disasters

5. **No secrets in git**
   - keep API keys in `.env` (ignored) or environment variables

---

## VS Code / Copilot prompts (exact + which file)

If you use VS Code’s AI assistant to apply changes, use prompts like these **verbatim**.

### Prompt A — Fix API metrics binding (compose)
**File:** `docker-compose.yml`

**Prompt:**
> Open `docker-compose.yml`. In the `api` service, set the environment variable `SYNQC_METRICS_BIND_ADDRESS` to `0.0.0.0` so Prometheus can scrape `api:9000` from another container. Do not change the API port mapping. Return only the minimal YAML diff.

### Prompt B — Add worker scrape to Prometheus
**File:** `docker/prometheus.yml`

**Prompt:**
> Open `docker/prometheus.yml` and add a second scrape job named `synqc-worker` that scrapes `worker:9001` at `/metrics`. Preserve the existing `synqc-api` job.

### Prompt C — Fix redis connectivity metric logic
**File:** `backend/synqc_backend/metrics.py`

**Prompt:**
> In `backend/synqc_backend/metrics.py`, update `_collect_budget_metrics` so the redis connectivity gauge treats any of these keys in `summary` as the redis connectivity flag: `redis_connected`, `redis_ok`, `ok`, `connected` (first non-None wins). Keep backend=="memory" as always-connected. Keep behavior otherwise unchanged. Provide only the final code block for `_collect_budget_metrics`.

### Prompt D — Ensure worker runs the correct queue consumer
**File:** `docker-compose.yml`

**Prompt:**
> In `docker-compose.yml`, update the `worker` service command so the container runs the run-queue consumer module (the one that processes the `synqc:runq:pending` list). Avoid using the legacy `worker_service` list queue. Provide only the YAML diff.

---

## Pre-PR / Pre-merge checklist

Before you open a PR:
1. `git status` is clean except intended files
2. No `docker-compose.override.yml` tracked
3. `docker compose up -d --build` works on a clean environment
4. `/health` is green
5. Prometheus targets show `synqc-api up` (and optionally `synqc-worker up`)
6. A run completes (`/runs/{id}` -> `succeeded`)
7. Grafana “Save & test” passes for Prometheus data source (optional but recommended)

---

## Appendix: Commands we used repeatedly

### Check which module the worker is running
```bash
docker compose exec worker sh -lc 'tr "\0" " " </proc/1/cmdline; echo'
```

### Inspect redis keys
```bash
docker compose exec redis redis-cli KEYS 'synqc:*'
```

### Restart a service
```bash
docker compose restart prometheus
docker compose up -d --force-recreate worker
```

---

## Notes on scope
This guide documents the sandbox build as a **local MVP**. If you deploy remotely, you’ll want:
- persistent volumes for Redis/Prometheus
- auth on Grafana and API
- HTTPS and proper ingress
- alerting rules + dashboards checked into the repo

---

**End of document**
