# Codex Next Steps (do in order, no scope creep)

## Step 1: Add parser + tests
Create:
- app/lib/conntrack/parser.rb
- spec/lib/conntrack/parser_spec.rb
- spec/fixtures/conntrack/*.txt

Requirements:
- Parser must parse conntrack-tools v1.4.7 `conntrack -L -o extended` output.
- Must support lines with and without `state` token.
- Must split ORIGINAL vs REPLY tuples using the 2nd occurrence of `src=`.
- Must parse per-tuple counters `packets=` and `bytes=` when present; default to 0 when absent.
- Must parse [FLAGS] like [ASSURED].
- Must parse trailing `mark=` and `use=` fields.
- Must ignore unknown tokens like zone=.

Tests:
- Add fixture lines based on real output from router.
- 3 test cases minimum: tcp w/ state+counters, tcp w/ state no counters, udp no state+counters.
- Parser returns nil for malformed lines (missing orig/src/dst or reply/src/dst).

## Step 2: Add “connection key” helper
Add Conntrack::Key.from_entry(entry) that returns stable 5-tuple key:
  "#{proto}|#{orig.src}|#{orig.sport}|#{orig.dst}|#{orig.dport}"

## Step 3: Implement a snapshot reader service (no DB yet)
Create Conntrack::Snapshot.read that runs:
  `conntrack -L -o extended`
and returns array of parsed Entry objects.

Must:
- run command safely, handle failures
- allow dependency injection for command output in tests

## Step 4: Wire a rake task to print outbound connections (dev tool)
Add rake task:
  rake conntrack:print_outbound
that:
- reads snapshot
- filters outbound per docs (LOCAL_SUBNETS in config/netmon.yml)
- prints top 20 by total bytes

# Codex next steps (after parser)

## Step 5: Implement outbound filter module + tests
- app/lib/netmon/filter.rb
- spec/lib/netmon/filter_spec.rb
Outbound if orig.src in LOCAL_SUBNETS and orig.dst not private/link-local/loopback.
LOCAL_SUBNETS loaded from config/netmon.yml (default 10.0.0.0/24).

## Step 6: Add ActiveRecord models + migrations
- RemoteHost(ip unique, first_seen_at, last_seen_at)
- Connection(proto, src_ip, src_port, dst_ip, dst_port, state, flags,
  uplink_packets, uplink_bytes, downlink_packets, downlink_bytes,
  first_seen_at, last_seen_at)
Unique index on (proto, src_ip, src_port, dst_ip, dst_port).

## Step 7: Snapshot reconciler + rake task
- app/lib/netmon/reconcile_snapshot.rb
- lib/tasks/netmon.rake task netmon:ingest_once
Reconciler must:
- read snapshot via Conntrack::Snapshot (support CONNTRACK_INPUT_FILE)
- parse + filter outbound
- upsert remote_hosts (by dst_ip)
- upsert connections (by 5-tuple)
- delete connections not seen in this run (or mark inactive)

Add tests using fixture replay.

## Step 8: Minimal dashboard
- DashboardController#index at /
- render active connections sorted by total bytes desc
- show "NEW" if remote_host.first_seen_at >= now-60s else "SEEN"
No websockets yet.

# Next Steps (9–10)

## Step 9: Continuous ingest loop
- Add `Netmon::Daemon.run(interval: 1.0)` that:
  - calls reconciler once per loop
  - sleeps interval
  - logs errors but keeps running
- Add rake task `netmon:ingest_loop` that runs daemon.
- If CONNTRACK_INPUT_FILE is set, loop replay (read file each iteration).

## Step 10: Live dashboard update via polling (no websockets)
- Add `ConnectionsController#index` (JSON) at `/connections.json`
  - returns current connections sorted by total bytes desc
  - includes seen_before boolean based on remote_hosts.first_seen_at threshold
- Update dashboard view to poll `/connections.json` every 1000ms and patch the table.
- Do NOT add ActionCable yet.

Constraints:
- Do not modify unrelated files.
- Only change files required for steps 9–10.
- Add/extend tests for daemon loop and JSON endpoint.

# CODEX_NEXT.md (Steps 9–12)

## Step 11: Continuous ingest loop (daemon)
Goal: keep DB updated continuously.

Deliverables:
- app/lib/netmon/daemon.rb
- lib/tasks/netmon.rake updated with task: netmon:ingest_loop

Requirements:
- Implement `Netmon::Daemon.run(interval: 1.0)`:
  - calls `Netmon::ReconcileSnapshot.run_once` (or existing reconciler entrypoint) every loop
  - sleeps `interval` seconds
  - logs exceptions but keeps running
- Rake task `netmon:ingest_loop` runs the daemon.
- Must support `CONNTRACK_INPUT_FILE` (fixture replay) the same way ingest_once does.
- Add tests for the daemon loop logic (at least: it calls reconciler; it sleeps; it continues after exception).

Acceptance:
- `CONNTRACK_INPUT_FILE=spec/fixtures/conntrack/router_extended.txt bin/rails netmon:ingest_loop`
  runs without crashing and updates DB repeatedly.

Constraints:
- Do not add ActionCable/WebSockets yet.
- Do not modify unrelated files.


## Step 12: Live dashboard updates via polling (no websockets)
Goal: dashboard updates without manual reload.

Deliverables:
- app/controllers/connections_controller.rb
- app/views/dashboard/index.html.erb updated with small JS poller
- config/routes.rb updated with:
  - GET /connections.json -> connections#index (JSON)

Requirements:
- `/connections.json` returns JSON array of current active connections sorted by total bytes desc.
- Each connection JSON must include:
  - proto, src_ip, src_port, dst_ip, dst_port
  - state, flags
  - uplink_bytes, downlink_bytes, total_bytes
  - last_seen_at
  - seen_before boolean:
    - true if RemoteHost.first_seen_at < (Time.now - 60 seconds)
    - false otherwise
- Dashboard page:
  - polls `/connections.json` every 1000ms
  - replaces only the `<tbody>` content (do not full-page reload)
  - keeps the page simple and fast

Acceptance:
- With ingest_loop running, open `/` and watch rows update live.

Constraints:
- No Stimulus required (plain JS is fine).
- No ActionCable yet.
- Do not modify unrelated files.


## Step 13: System metrics endpoint + UI tiles
Goal: show system health and interface counters.

Deliverables:
- app/lib/netmon/metrics.rb
- app/controllers/metrics_controller.rb
- GET /metrics.json route
- dashboard view updated to show tiles for:
  - loadavg (1/5/15)
  - memory used/total
  - interface stats for configured interfaces

Requirements:
- Metrics sources:
  - /proc/loadavg
  - /proc/meminfo
  - /sys/class/net/<iface>/statistics/rx_bytes, tx_bytes, rx_packets, tx_packets
- Config:
  - config/netmon.yml must include:
    - monitor_interfaces: ["enp2s0", "enp3s0"]  # router default
- In dev, allow overriding interfaces via env var:
  - NETMON_INTERFACES=enp42s0

Acceptance:
- `curl http://localhost:3000/metrics.json` returns valid JSON.
- Dashboard updates metrics every 2000ms (polling ok).


## Step 14: Router deployment scaffolding (systemd + binding)
Goal: run on router reliably and safely.

Deliverables:
- deploy/systemd/netmon-ingest.service
- deploy/systemd/netmon-web.service (optional)
- deploy/README.md

Requirements:
- netmon-ingest.service runs:
  - `bin/rails netmon:ingest_loop`
- Web service binds to LAN only (10.0.0.1) OR documents how to do so.
- Document required router settings:
  - net.netfilter.nf_conntrack_acct=1
  - conntrack-tools installed

Constraints:
- Do not attempt privilege separation yet unless easy.
- Keep deployment docs minimal and accurate.


## Global Guardrails
- Before committing, show `git diff --stat`.
- Revert any changes outside the listed deliverables unless explicitly justified.
- Do NOT change Gemfile/Gemfile.lock unless explicitly required.
