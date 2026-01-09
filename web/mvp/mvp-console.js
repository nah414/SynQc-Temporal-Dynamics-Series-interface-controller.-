function $(id) { return document.getElementById(id); }

function pretty(x) {
  try { return JSON.stringify(x, null, 2); } catch { return String(x); }
}

// Use direct host-exposed API. This keeps MVP independent of any nginx proxy rules.
const API_BASE = "/api";

const GRAFANA_URL = "http://127.0.0.1:3000";
const PROM_URL    = "http://127.0.0.1:9090";

async function get(path) {
  const url = `${API_BASE}${path}`;
  const r = await fetch(url);
  const t = await r.text();
  let data = t;
  try { data = JSON.parse(t); } catch {}
  if (!r.ok) throw new Error(`GET ${url} -> ${r.status}\n${t}`);
  return data;
}

async function post(path, body) {
  const url = `${API_BASE}${path}`;
  const r = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const t = await r.text();
  let data = t;
  try { data = JSON.parse(t); } catch {}
  if (!r.ok) throw new Error(`POST ${url} -> ${r.status}\n${t}`);
  return data;
}

function setStatus(ok, msg) {
  const el = $("mvp_status");
  if (!el) return;
  el.textContent = msg;
  el.dataset.ok = ok ? "1" : "0";
}

async function health() {
  setStatus(false, "Checking backend…");
  try {
    const h = await get("/health");
    setStatus(true, `Backend OK: ${pretty(h)}`);
  } catch (e) {
    // fallback to /metrics if health isn't available
    try {
      await get("/metrics");
      setStatus(true, "Backend OK (/metrics reachable)");
    } catch {
      setStatus(false, `Backend NOT reachable.\n${e.message}`);
    }
  }
}

async function runGroverDryRun() {
  $("mvp_result").textContent = "";
  $("mvp_job").textContent = "(submitting)";
  setStatus(false, "Submitting Grover dry-run…");

  const payload = {
    agent: "grover_search",
    sandbox: "grover",
    dry_run: true,
    prompt: $("mvp_prompt").value || "Grover sandbox received prompt (dry_run)"
  };

  const resp = await post("/jobs", payload);
  const jobId = resp.job_id || resp.id || resp?.result?.job_id;

  if (!jobId) {
    $("mvp_result").textContent = pretty(resp);
    setStatus(false, "No job_id returned from POST /jobs");
    return;
  }

  $("mvp_job").textContent = jobId;
  await poll(jobId);
}

async function poll(jobId) {
  const start = Date.now();
  const timeoutMs = 60_000;

  while (true) {
    const data = await get(`/jobs/${jobId}?include_result=true`);
    $("mvp_result").textContent = pretty(data);

    const status = data.status || data.state;
    if (status === "succeeded" || status === "failed" || status === "canceled") {
      setStatus(status === "succeeded", `Job finished: ${status}`);
      return;
    }

    if (Date.now() - start > timeoutMs) {
      setStatus(false, "Timed out waiting for job.");
      return;
    }

    await new Promise(r => setTimeout(r, 700));
  }
}

function wireLinks() {
  $("mvp_link_console").href = "http://127.0.0.1:8080/";
  $("mvp_link_grafana").href = GRAFANA_URL;
  $("mvp_link_prom").href = PROM_URL;
  $("mvp_link_metrics").href = `${API_BASE}/metrics`;
}

function wire() {
  $("mvp_btn_health").addEventListener("click", health);
  $("mvp_btn_run").addEventListener("click", runGroverDryRun);
  wireLinks();
  health();
}

wire();
