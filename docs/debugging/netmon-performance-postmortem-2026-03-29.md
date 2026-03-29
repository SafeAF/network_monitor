# Netmon Performance Postmortem - 2026-03-29

## Summary

The app was slow on `beefies` because normal page requests were waiting behind expensive live ingest requests to `/api/v1/netmon/events/batch`.

This was not primarily a view or asset problem by the time of this incident. The server was running Rails in `development` with SQLite, a single long-lived Puma process under `foreman`, and a continuous stream of ingest batches from the router. Many of those batch requests were taking multiple seconds and issuing thousands of SQL queries.

The fix reduced repeated work in the ingest path and lowered long-running development-mode overhead.

Commit:

- `9a2088e` `Reduce live ingest overhead`

## Environment

- Host: `user@beefies`
- App path: `~/source/network_monitor/netmon`
- Rails env: `development`
- DB: `storage/development.sqlite3`
- App server: `foreman` running one Puma process

## Request Path Model

To reason about the slowdown, I used this path:

1. Browser requests HTML.
2. App server accepts request.
3. Router sends to controller.
4. Controller triggers DB work and model logic.
5. View renders HTML.
6. Browser downloads assets.
7. Browser paints and starts follow-up polling.

The important distinction was whether the delay was:

- before the app started responding
- inside controller/model code
- inside rendering
- in asset fetches
- in the browser after the response arrived

## Investigation Timeline

### Step 1: Confirm the issue on the real server

- Symptom: User reported 20+ second page loads on `beefies`.
- Suspected layer: Unknown.
- Measurement taken: SSH into `beefies`, inspect running app, inspect logs, benchmark with on-box `curl`.
- Result: Slow responses reproduced from the server itself.
- Conclusion: Not a local dev machine issue. Not primarily a browser-network issue.
- Next action: Determine whether the slow path was HTML rendering, assets, or request starvation.

### Step 2: Verify the latest performance fixes were actually deployed

- Symptom: Previous local fixes might not exist on `beefies`.
- Suspected layer: Deploy drift.
- Measurement taken: `rg` for the known dashboard and asset fixes in the remote checkout.
- Result: The newer asset and dashboard polling fixes were already present on `beefies`.
- Conclusion: The remaining slowness was a different bottleneck.
- Next action: Measure live response times and inspect request logs.

### Step 3: Check system health

- Symptom: App felt globally slow.
- Suspected layer: Machine resource exhaustion.
- Measurement taken: `uptime`, `free -h`, `vmstat`, process list.
- Result:
  - Machine CPU mostly idle overall.
  - Memory not exhausted.
  - One Puma process near 100% CPU.
- Conclusion: The host was not overloaded globally. One application process was hot.
- Next action: Identify what that Puma process was spending time on.

### Step 4: Verify runtime mode and data volume

- Symptom: Long-lived live app might be running in a poor configuration.
- Suspected layer: Environment / operational setup.
- Measurement taken: Rails runner on `beefies` for env, adapter, DB path, and table counts.
- Result:
  - `development`
  - `SQLite3Adapter`
  - `storage/development.sqlite3`
  - `connections`: ~509k
  - `netmon_events`: ~6.18M
  - `dns_events`: ~229k
- Conclusion: This is a live workload on development + SQLite with significant data volume.
- Next action: Still measure the actual hot path instead of assuming SQLite alone explains all latency.

### Step 5: Benchmark the slow pages directly on-box

- Symptom: User-facing pages felt slow.
- Suspected layer: HTML generation, DB, or queueing.
- Measurement taken: `curl -w` from `127.0.0.1:3000` for:
  - `/`
  - `/search`
  - `/search/hosts`
  - `/search/connections`
  - `/anomalies`
  - `/remote_hosts/10.0.0.10`
- Result before fix:
  - `/search`: ~8.18s
  - `/search/hosts`: ~3.78s
  - `/search/connections`: ~4.23s
  - `/anomalies`: ~3.77s
  - `/remote_hosts/10.0.0.10`: ~4.72s
- Conclusion: The app was genuinely slow server-side.
- Next action: Check whether the HTML itself was huge or expensive to render.

### Step 6: Rule out oversized HTML on `/search`

- Symptom: `/search` was slow even though it should be simple.
- Suspected layer: Unexpected response bloat.
- Measurement taken:
  - Fetch raw HTML
  - Count tags/payload size
  - Inspect source
- Result:
  - HTML size only about 6 KB
  - No large tables
  - No giant inline payload
- Conclusion: `/search` was not slow because it rendered a huge page.
- Next action: Look for request starvation or competing server work.

### Step 7: Correlate slow pages with Rails logs

- Symptom: Simple pages were still delayed.
- Suspected layer: App server queueing.
- Measurement taken: Tail recent `development.log` and match timestamps around the curl runs.
- Result:
  - Pages like `/search` often showed tiny own work once they started.
  - At the same time, many `/api/v1/netmon/events/batch` requests were in flight.
  - Those batch requests frequently took 5 to 12 seconds.
  - Query counts often landed around 3,800 to 5,000 per batch.
- Conclusion: Regular HTML requests were waiting behind ingest work.
- Next action: Inspect the ingest path and find repeated expensive work.

### Step 8: Inspect the ingest code path

- Symptom: Batch ingest requests were doing too much work.
- Suspected layer: Controller/model hot path.
- Measurement taken: Read:
  - `app/controllers/api/v1/netmon/events_controller.rb`
  - `app/lib/netmon/agent_ingest.rb`
  - `app/lib/netmon/anomaly/device_stats.rb`
  - `app/lib/netmon/anomaly/scorer.rb`
- Result:
  - Every event called into `Netmon::AgentIngest`.
  - Every flow re-ran DNS correlation.
  - Every flow re-ran device stats aggregation queries.
  - Every flow re-ran anomaly scoring.
  - Anomaly scoring reloaded config from YAML on each call.
  - Device stats performed an extra device-IP lookup pattern.
  - Repeated `DESTROY` updates on already-known connections were paying almost the same cost as first-seen flows.
- Conclusion: The hot path was dominated by repeated per-flow model/query work that was unnecessary for terminal updates.
- Next action: Cut repeated work while preserving behavior.

## Dead Ends And Ruled-Out Causes

### Dead end: asset pipeline as primary cause

- Why suspected: We had previously found CSS asset issues on another slowdown.
- Measurement taken: Inspect live HTML and asset references.
- Result: Assets were correctly linked and the page body was small.
- Conclusion: Not the primary cause of this incident.

### Dead end: huge page HTML

- Why suspected: Browser showed long waits on page loads.
- Measurement taken: Fetch raw `/search` HTML and measure size.
- Result: HTML was small.
- Conclusion: Not response size.

### Dead end: server under global CPU or memory pressure

- Why suspected: Whole app felt slow.
- Measurement taken: `uptime`, `free`, `vmstat`.
- Result: System mostly idle except for one hot Puma process.
- Conclusion: Not host-wide exhaustion.

### Dead end: stale deploy

- Why suspected: Remote server might not have local fixes.
- Measurement taken: Inspect remote source for prior performance patches.
- Result: Those were already present.
- Conclusion: Remaining issue was elsewhere.

## Important Signals That Mattered

These were the highest-signal clues:

- `curl` from localhost was also slow.
  - This ruled out client/network as the primary cause.
- `/search` HTML was tiny.
  - This ruled out response-size/render bloat for that page.
- Puma was near 100% CPU while the rest of the server was mostly idle.
  - This pointed to one application hot path.
- Rails logs showed `/api/v1/netmon/events/batch` constantly in flight.
  - This identified the request class starving the app.
- Batch requests showed 3,800 to 5,000 SQL queries and multi-second durations.
  - This proved the bottleneck was repeated DB-backed model logic inside ingest.

## Code Changes

### 1. Skip repeated expensive work for known terminal flow updates

File:

- [agent_ingest.rb](/home/user/source/network_monitor/netmon/app/lib/netmon/agent_ingest.rb#L45)

Changes:

- Track whether the connection is new.
- Only refresh DNS correlation if the connection does not already have a domain.
- Only re-run anomaly scoring when:
  - the connection is new
  - anomaly fields are missing
  - the flow state is `NEW` or `SYN_SENT`

Why this mattered:

- Repeated `DESTROY` updates were paying for full anomaly and DNS work even though they usually added no new classification value.

### 2. Remove one extra device lookup from device stats

File:

- [device_stats.rb](/home/user/source/network_monitor/netmon/app/lib/netmon/anomaly/device_stats.rb#L17)

Changes:

- Pass `device_ip` directly when known.
- Avoid an extra `Device.where(id: ...).select(:ip)` pattern for each stats calculation.

Why this mattered:

- Small per-call savings matter when the code runs for many events per batch.

### 3. Cache the anomaly scorer config

File:

- [scorer.rb](/home/user/source/network_monitor/netmon/app/lib/netmon/anomaly/scorer.rb#L8)

Changes:

- Cache parsed `config/netmon.yml` in `Rails.cache` for 5 minutes.

Why this mattered:

- Avoid repeated file reads and YAML parsing on the ingest hot path.

### 4. Lower long-running development overhead

File:

- [development.rb](/home/user/source/network_monitor/netmon/config/environments/development.rb#L15)

Changes:

- Server timing only when explicitly enabled.
- Lower default log verbosity.
- Disable verbose query log annotations unless requested.
- Disable verbose enqueue logs unless requested.
- Disable view filename annotations unless requested.

Why this mattered:

- `beefies` was running as a live long-lived dev server. Development-mode logging overhead made an already-hot path worse and also bloated responses when view annotations were enabled.

## Before/After Measurements

### Page timings

Before:

- `/search`: ~8.18s
- `/search/hosts`: ~3.78s
- `/search/connections`: ~4.23s
- `/anomalies`: ~3.77s
- `/remote_hosts/10.0.0.10`: ~4.72s

After pull and Rails restart:

- `/search`: ~1.34s
- `/search/hosts`: ~1.33s
- `/search/connections`: ~1.20s
- `/anomalies`: ~0.73s
- `/remote_hosts/10.0.0.10`: ~1.92s

### Ingest timings

Before:

- Frequent batch requests at 5 to 12 seconds
- Common query counts around 3,800 to 5,000

After:

- Most batch requests tens to hundreds of milliseconds
- Many requests down to 5 to 300 queries
- Some larger bursts still exist, but far fewer multi-second monopolizers

## Per-Step Investigation Log

### Step A

- Symptom: Every page was slow.
- Suspected layer: Unknown.
- Measurement taken: Reproduce on `beefies` directly.
- Result: Slow locally on the server too.
- Conclusion: Not a local browser-only issue.
- Next action: Isolate server-side layer.

### Step B

- Symptom: Search page slow despite simple UI.
- Suspected layer: Rendering or assets.
- Measurement taken: Fetch raw HTML and inspect asset references.
- Result: Small HTML, normal asset links.
- Conclusion: Not primarily render/asset size.
- Next action: Look for request starvation.

### Step C

- Symptom: App slow while box seemed otherwise healthy.
- Suspected layer: App server contention.
- Measurement taken: `ps`, `uptime`, `vmstat`.
- Result: One Puma hot, system otherwise fine.
- Conclusion: Hot request path inside Rails.
- Next action: Identify dominating endpoint.

### Step D

- Symptom: Ordinary pages start responding late.
- Suspected layer: Competing endpoint load.
- Measurement taken: Tail Rails logs around reproductions.
- Result: `/api/v1/netmon/events/batch` dominating runtime.
- Conclusion: Ingest path starving page requests.
- Next action: Inspect ingest path source.

### Step E

- Symptom: Batch requests use thousands of queries.
- Suspected layer: Per-event repeated work.
- Measurement taken: Read ingest/anomaly code.
- Result: DNS correlation, device stats, anomaly scoring, and config loads repeated on every flow update.
- Conclusion: Hot path needs reduction, not superficial page tuning.
- Next action: Skip unnecessary work for already-known terminal updates.

### Step F

- Symptom: Long-running live server in development mode.
- Suspected layer: Logging/debug overhead.
- Measurement taken: Inspect Rails env and dev config.
- Result: Live app in `development`, verbose dev settings active until restart.
- Conclusion: Secondary multiplier of latency.
- Next action: Quiet default dev settings and restart Rails.

## Which Tools Answered Which Question

### `ssh`

- Is the problem real on the live box?
- What code and process is actually running?

### `curl` from localhost

- Is the slowness inside the server or outside it?
- What are real first-byte and total-response times?

### Rails logs

- Which endpoint is consuming time?
- Was it DB-heavy, render-heavy, or queueing?
- How many queries were executed?

### `ps`, `uptime`, `vmstat`, `free`

- Is the whole machine overloaded?
- Is one process saturated?

### Source inspection with `sed` / `rg`

- Which code path corresponds to the hot endpoint?
- Where is repeated per-event work happening?

### `sqlite3` / Rails runner

- What DB backend and table sizes are in play?
- Is the app using a dev SQLite DB with live volume?

### RSpec

- Did the optimization preserve behavior?
- Can we lock in the new hot-path rules?

## Short Postmortem

### Root cause

Live page requests were queued behind very expensive `/api/v1/netmon/events/batch` ingest requests. Those ingest requests were repeatedly recalculating DNS correlation and anomaly state for already-known flow updates.

### Why it caused slowness

The app was running a live workload in Rails `development` on SQLite with one Puma process under `foreman`. When ingest monopolized that process, ordinary pages had to wait their turn. The cost was amplified by development-mode overhead.

### How to recognize this pattern next time

Look for this combination:

- tiny/simple pages still slow
- localhost `curl` still slow
- one app process hot while the server is otherwise fine
- slow logs dominated by an API or polling endpoint unrelated to the page being viewed
- high query counts rather than just one slow query

If you see that pattern, stop optimizing the page first. Find the competing hot path that is starving the server.
