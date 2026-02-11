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

# Next Steps (11–13)

## Step 11: Seen age + NEW window
- Add helper methods for remote host:
  - seen_age (human readable)
  - new? (first_seen_at within 60s)
- Update UI to show age and NEW/SEEN badge.

## Step 12: Filters and sorting
- Add query params:
  - src_ip, dst_ip, dport, proto
  - hide_time_wait=true
  - only_new=true
- Default sort: total_bytes desc
- Add links/buttons in UI to apply filters.

## Step 13: System metrics tiles
- Implement Netmon::Metrics reading:
  - /proc/loadavg
  - /proc/meminfo
  - /sys/class/net/<iface>/statistics/*
- Add /metrics.json endpoint
- Update dashboard to poll metrics every 2s and display tiles.
- Interfaces configured in config/netmon.yml

# CODEX_NEXT.md — Delta accounting + per-device naming + baselines + anomaly scoring + review log + Top-N

## Goal
Turn the current live conntrack dashboard into a practical anomaly detector with:
- Correct time-window metrics via **delta accounting** (conntrack counters are cumulative)
- **Device naming** for internal IPs (10.0.0.20 -> "ChoochDesktop")
- Rolling **minute buckets** and **baselines** per device
- Deterministic **anomaly scoring** (0–100) with stored “reasons”
- Persisted **Anomaly Hits** for review (with de-dup)
- “Top N” panels driven by minute buckets (not by raw cumulative counters)

Constraints:
- Do not change conntrack parser semantics (orig vs reply, outbound selection by IP ranges).
- Avoid new external dependencies; do not edit Gemfile/Gemfile.lock unless explicitly required.
- Keep tables bounded with cleanup tasks.
- Provide unit tests for delta logic, scoring rules, and hit de-dup.

Current schema (as of now):
- connections: stores proto/src/dst/state/flags and *cumulative* uplink/downlink bytes/packets.
- remote_hosts: has ip + first/last seen + rDNS/WHOIS.
- metric_samples exists but is too coarse; keep it for now or deprecate later.

---

## Step 14 — Add device naming for internal hosts
### Migration + model
Create table `devices`:
- ip (string, NOT NULL, unique)  # 10.0.0.20
- name (string, NOT NULL, default "")
- notes (string, nullable)
- first_seen_at (datetime, NOT NULL)
- last_seen_at (datetime, NOT NULL)

Indexes:
- unique index on ip

### Ingest behavior
During ingest/reconcile:
- upsert Device by `src_ip` for every outbound connection
- update last_seen_at each cycle
- set first_seen_at on creation

### UI
- Show “Device” column in connections table (Device.name if present else src_ip)
- Add a minimal edit form:
  - `/devices` index with inline edit, OR
  - inline edit on dashboard (PATCH /devices/:id)
Prefer a simple `/devices` page with a table and edit fields.

Tests:
- device upsert created + last_seen_at updates

---

## Step 15 — Add delta accounting fields to `connections` (correct windowed metrics)
Conntrack `bytes=`/`packets=` are cumulative per-flow. We must compute deltas per ingest.

### Migration
Add to `connections`:
- last_uplink_bytes (bigint, default 0, null false)
- last_downlink_bytes (bigint, default 0, null false)
- last_uplink_packets (bigint, default 0, null false)
- last_downlink_packets (bigint, default 0, null false)
- last_delta_at (datetime, nullable)

Add optional anomaly fields to connections now (used later):
- anomaly_score (int, default 0, null false)
- anomaly_reasons_json (text, default "[]", null false)

### Delta algorithm (must implement exactly)
For each parsed conntrack entry mapping to a Connection row:
- current counters from entry:
  - cur_up_b = entry.orig.bytes (default 0)
  - cur_dn_b = entry.reply.bytes (default 0)
  - cur_up_p = entry.orig.packets (default 0)
  - cur_dn_p = entry.reply.packets (default 0)

Fetch existing connection row by 5-tuple.

If connection exists:
- d_up_b = max(cur_up_b - conn.last_uplink_bytes, 0)
- d_dn_b = max(cur_dn_b - conn.last_downlink_bytes, 0)
- d_up_p = max(cur_up_p - conn.last_uplink_packets, 0)
- d_dn_p = max(cur_dn_p - conn.last_downlink_packets, 0)

If connection is new:
- set all deltas to 0 for first sighting (avoid first-ingest spike artifacts)

Always update:
- conn.uplink_bytes = cur_up_b
- conn.downlink_bytes = cur_dn_b
- conn.uplink_packets = cur_up_p
- conn.downlink_packets = cur_dn_p
- conn.last_* = cur_*
- conn.last_delta_at = now
- conn.last_seen_at = now

Note: deltas drive minute buckets; cumulative fields remain for “active flow total so far”.

Tests:
- delta clamp when counters reset (negative -> 0)
- new connection produces 0 delta
- existing connection produces expected delta

---

## Step 16 — Add minute buckets for per-device + per-remote rollups
### Migrations
Create `device_minutes`:
- device_id (FK)
- bucket_ts (datetime truncated to minute, NOT NULL)
- conn_count (int, default 0)
- uplink_bytes (bigint, default 0)
- downlink_bytes (bigint, default 0)
- uplink_packets (bigint, default 0)
- downlink_packets (bigint, default 0)
- new_dst_ips (int, default 0)
- unique_dst_ips (int, default 0)
- unique_dst_ports (int, default 0)
- unique_dst_asns (int, default 0)
- unique_protos (int, default 0)
- rare_ports (int, default 0)

Unique index (device_id, bucket_ts). Index on bucket_ts.

Create `remote_host_minutes`:
- remote_host_id (FK)
- bucket_ts (datetime truncated to minute, NOT NULL)
- conn_count (int, default 0)
- uplink_bytes (bigint, default 0)
- downlink_bytes (bigint, default 0)
- uplink_packets (bigint, default 0)
- downlink_packets (bigint, default 0)

Unique index (remote_host_id, bucket_ts). Index on bucket_ts.

### Bucket update behavior (during ingest)
For each outbound connection processed:
- determine bucket_ts = now.utc with seconds=0
- attribute DELTAS (d_up_b/d_dn_b/d_up_p/d_dn_p) to:
  - DeviceMinute for device(src_ip)
  - RemoteHostMinute for remote_host(dst_ip)

Also compute per-device “uniques” per ingest cycle using Ruby Sets:
- dst_ips_set
- dst_ports_set
- dst_asns_set (use remote_host.whois_asn if present, else whois_name fallback)
- proto_set
- rare_ports_count: count of dport not in COMMON_PORTS

At end of ingest cycle, for each device’s bucket row:
- set unique_dst_ips = dst_ips_set.size
- set unique_dst_ports = dst_ports_set.size
- set unique_dst_asns = dst_asns_set.size
- set unique_protos = proto_set.size
- set rare_ports = rare_ports_count

Compute new_dst_ips in this cycle:
- count dst_ips where remote_host.first_seen_at within NEW_WINDOW_SECONDS

Tests:
- minute bucket created and updated
- rollups reflect delta attribution

---

## Step 17 — Baselines per device (rolling p95-like thresholds)
Do NOT overcomplicate. Implement a robust baseline recomputation job that stores a small set of threshold values.

### Migration
Create `device_baselines`:
- device_id (FK, unique)
- window_minutes (int, default BASELINE_WINDOW_MINUTES) # e.g. 60
- p95_uplink_bytes_per_min (bigint, default 0)
- p95_conn_count_per_min (int, default 0)
- p95_new_dst_ips_per_10m (int, default 0)
- p95_unique_ports_per_10m (int, default 0)
- updated_at

Index unique on device_id.

### Recompute service
Implement `Netmon::Baseline::Recompute.run(now: Time.now.utc)`:
- for each device, look back last 24h of device_minutes
- compute:
  - p95_uplink_bytes_per_min: p95 of uplink_bytes over 1-minute buckets
  - p95_conn_count_per_min: p95 of conn_count over 1-minute buckets
  - p95_new_dst_ips_per_10m: p95 over 10-minute window sums of new_dst_ips
  - p95_unique_ports_per_10m: p95 over 10-minute window max(unique_dst_ports) or sum; pick one and keep consistent (prefer max)

Implementation detail:
- p95 can be approximated by sorting values and taking index ceil(0.95*n)-1.
- handle empty data (baseline stays 0).

Add rake task:
- `netmon:recompute_baselines`

Tests:
- recompute produces expected values on synthetic minute rows

---

## Step 18 — Anomaly scoring engine (per active connection + per-device events)
### Config (config/netmon.yml)
Add:
- common_ports: [53, 80, 123, 443]
- common_protos: ["tcp", "udp"]
- new_window_seconds: 600
- anomaly_threshold: 50
- dedup_suppress_seconds: 600
- baseline_window_minutes: 60
- dormant_remote_days: 30
- high_fanout_threshold: 30
- high_unique_ports_threshold: 20

### Scorer
Implement `Netmon::Anomaly::Scorer.score_connection(connection:, device:, remote_host:, baseline:, device_stats:)` returning:
- score (0..100)
- reasons (array of hashes: {code, weight, detail})

Rules (v1):
1) NEW_DST (+30): remote_host.first_seen_at within NEW_WINDOW_SECONDS
2) DORMANT_DST (+15): remote_host.last_seen_at < now - dormant_remote_days
3) NEW_ASN (+20): remote ASN/org not seen by this device in last 7d
   - implement by looking at device_minutes unique_dst_asns history (simple) OR a small join table if needed later
4) RARE_PORT (+25): dst_port not in common_ports
   - special-case: UDP 443 (QUIC) weight lower (+5) or informational
5) UNEXPECTED_PROTO (+20): proto not in common_protos
6) NO_RDNS (+10): remote_host.rdns_name blank
7) HIGH_EGRESS (+25): device uplink_bytes_last_10m > baseline.p95_uplink_bytes_per_min * 10 * 3
8) HIGH_FANOUT (+25): device new_dst_ips_last_10m > max(baseline.p95_new_dst_ips_per_10m*3, high_fanout_threshold)
9) PORT_SCAN_LIKE (+25): device unique_ports_last_10m > max(baseline.p95_unique_ports_per_10m*3, high_unique_ports_threshold)

Clamp score to 0..100.

Store on Connection row each ingest:
- anomaly_score
- anomaly_reasons_json (JSON array)

Tests:
- each rule triggers correctly
- QUIC special-case
- clamp works
- stable reason formatting

---

## Step 19 — Persist anomaly hits with de-dup and review page
### Migration
Create `anomaly_hits`:
- occurred_at (datetime, NOT NULL)
- device_id (FK)
- remote_host_id (FK, nullable)
- proto (string)
- src_ip (string)
- dst_ip (string)
- dst_port (int)
- score (int)
- total_bytes (bigint, default 0)
- summary (string)
- reasons_json (text, default "[]")
- fingerprint (string, indexed)
- suppressed_until (datetime, nullable)

Indexes:
- occurred_at
- device_id, occurred_at
- dst_ip, occurred_at
- fingerprint

### De-dup rule
fingerprint = "#{device_id}|#{dst_ip}|#{dst_port}|#{proto}|#{sorted_reason_codes.join(',')}"
When emitting a hit:
- if a hit exists with same fingerprint and occurred_at within last dedup_suppress_seconds: skip
- else create hit

### Emission policy
During ingest after scoring:
- if connection.anomaly_score >= anomaly_threshold:
  - emit AnomalyHit (if not deduped)
- also emit DEVICE-LEVEL hits (optional) when HIGH_FANOUT or PORT_SCAN_LIKE triggers even if individual connections are low; include dst_ip=nil.

### UI
Add `/anomalies` page:
- list anomaly hits ordered desc
- filters: min_score, device, code substring, dst_ip, dst_port, last 1h/24h/7d
- expand row to show reasons_json

Tests:
- dedup suppression works
- anomalies page responds and filters correctly

---

## Step 20 — UI enhancements: add score column + reasons + Top-N panels
### Dashboard table additions
Add columns:
- Device (name/ip)
- Anomaly Score (badge)
- Reasons (compact codes, hover/expand for detail)
- rDNS + WHOIS remain

### Top-N panels (driven from minute tables)
Implement helper queries:
1) Top Remote Hosts (last 10m) by total bytes:
   - sum remote_host_minutes uplink+downlink over last 10 buckets
2) Newest Remote Hosts (last 10m):
   - remote_hosts where first_seen_at > now-10m, sorted desc
3) Rare Ports (last 24h) by count:
   - use device_minutes.rare_ports and/or compute from recent connections grouped by dst_port where not common
4) Devices by Egress (last 10m):
   - sum device_minutes.uplink_bytes over last 10 buckets, join devices

Add “only anomalies” filter:
- min_score quick buttons: 0 / 20 / 50

Optional: poll endpoints every 1–2 seconds (existing approach ok).

---

## Step 21 — Cleanup tasks (bound table growth)
Add rake task `netmon:cleanup`:
- delete device_minutes older than 30 days (configurable)
- delete remote_host_minutes older than 30 days
- delete anomaly_hits older than 90 days (configurable)

Tests:
- cleanup removes old rows

---

## Implementation notes (must follow)
- Use transaction per ingest cycle.
- Use upsert/bulk insert where possible to avoid N+1.
- Keep reason JSON small; store only codes + short details.
- Do not block ingest on rDNS/WHOIS lookups; those should remain rate-limited and optional.

---

## Deliverables checklist
- [ ] devices + UI edit path
- [ ] delta fields on connections + correct delta computation
- [ ] device_minutes + remote_host_minutes updated via deltas
- [ ] device_baselines recompute + rake task
- [ ] anomaly scorer + stored scores/reasons on connections
- [ ] anomaly_hits with dedup + /anomalies page
- [ ] top-N panels on dashboard driven by minute buckets
- [ ] cleanup rake task
- [ ] tests for delta, scorer, dedup, baseline recompute
- [ ] show `git diff --stat` before finishing; revert unrelated edits

# CODEX_NEXT.md — Search + Saved Queries + Allow/Suppress + Scoring fixes + Investigation UX

## Decision
Do NOT wipe. Extend the existing system:
- You already have live ingest + charts + per-remote-host page.
- Next work is investigation UX + noise reduction + review workflow.

Constraints:
- No new dependencies unless absolutely required.
- All new queries must be indexed and fast.
- Make everything screenshot-safe (redaction mode optional but recommended).
- Keep scoring explainable; persist reasons/codes when scoring triggers.
- Provide tests for filter parsing + scoring changes + allow/suppress behavior.

---

## Step 22 — Add Search pages (hosts / connections / anomalies)
### Routes
- GET /search (redirect to /search/hosts)
- GET /search/hosts
- GET /search/connections
- GET /search/anomalies

### UI pattern (shared)
- Filter form at top
- Results table below
- “Save Query” button (stores current params)
- “Load Saved Query” dropdown

### Filters to implement

#### /search/hosts (RemoteHosts)
Filters:
- ip (exact / prefix)
- whois_name contains
- whois_asn contains
- rdns contains
- rdns missing (true/false)
- first_seen within (1h/24h/7d/30d)
- last_seen within (1h/24h/7d/30d)
- seen_port = N (host has ever been contacted on dst_port N)
- min_total_bytes_ever (computed from connections aggregate; see notes)
- min_max_score_ever (if connection scores are stored)

Sort:
- last_seen desc (default)
- first_seen desc
- max_total_bytes desc
- max_score desc

Result rows link to the existing per-host page.

Implementation notes:
- “seen_port” requires either:
  A) a `remote_host_ports` summary table, or
  B) query from `connections` (but connections is a snapshot, not history).
Prefer A.

#### /search/connections
Filters:
- device (by name or src_ip)
- src_ip
- dst_ip
- dst_port
- proto
- state (hide TIME_WAIT)
- min_score (0/20/50)
- reason contains (e.g. RARE_PORT)
- only_new_dst (dst first_seen within new_window)

Sort:
- score desc (default)
- total_bytes desc
- last_seen desc

#### /search/anomalies (AnomalyHits)
Filters:
- device
- dst_ip
- dst_port
- min_score
- code (contains)
- time range (1h/24h/7d/30d)

Sort:
- occurred_at desc (default)

---

## Step 23 — Saved Queries
Create `saved_queries` table:
- name (string, NOT NULL)
- kind (string, NOT NULL) # "hosts"|"connections"|"anomalies"
- params_json (text, NOT NULL) # JSON
- created_at

UI:
- On each /search page: “Save” button prompts for name
- Dropdown to load a saved query

Tests:
- saving and loading preserves params correctly
- invalid JSON rejected

---

## Step 24 — Host Port History (make seen_port possible)
Problem: `connections` is a current snapshot. Search needs “host has ever been seen on port X”.

Create `remote_host_ports`:
- remote_host_id
- dst_port (int)
- first_seen_at
- last_seen_at
- seen_count (int)
Unique index (remote_host_id, dst_port).

Ingest:
- whenever we see a connection to dst_ip:dst_port:
  - upsert remote_host_ports and bump last_seen_at, seen_count

UI:
- On host page show list of ports with first/last seen + count.
- On /search/hosts implement `seen_port=N` via this table.

Tests:
- port history upserts and counts

---

## Step 25 — Fix PORT_SCAN_LIKE false positives (make scoring trustworthy)
Current behavior (observed): PORT_SCAN_LIKE triggers on normal 443-heavy browsing.

Replace PORT_SCAN_LIKE rule with a higher-signal definition:

Compute per device over last 10 minutes:
- unique_dst_ports_10m
- unique_dst_ips_10m
- top_port_share_10m (fraction of connections using the most common port)

Trigger PORT_SCAN_LIKE only if ALL:
- unique_dst_ports_10m >= 20
- unique_dst_ips_10m >= 20
- top_port_share_10m <= 0.80  (if most traffic is one port, it’s not a scan)

Implementation:
- add these aggregates to the existing 10m rollup service (or minute buckets)
- store top_port_share_10m in MetricSamples or compute on the fly from minute buckets.

Tests:
- browsing scenario (mostly 443) does NOT trigger
- synthetic scan scenario does trigger

Also: lower weight of NO_RDNS or make it conditional:
- If whois_name is a major CDN org (Cloudflare/Fastly/Amazon/Google/Microsoft), NO_RDNS weight => 0 or 2.

---

## Step 26 — Allowlist + Suppression (reduce noise, keep signal)
Create `allowlist_rules` table:
- kind (string) # "asn"|"org"|"rdns_suffix"|"ip"|"port"|"device_port"
- value (string) # e.g. "CLOUD14" or "cloudfront.net" or "104.16.0.0/12" (start simple: exact)
- device_id (nullable) # for device_port allowlist
- created_at
- notes

Create `suppression_rules` table:
- code (string) # reason code to suppress
- kind/value/device_id same pattern as allowlist
- created_at
- notes

Behavior:
- Scorer consults allowlist/suppression:
  - If dst org/asn is allowlisted, suppress NO_RDNS and lower NEW_DST weight.
  - If dst_port is allowlisted for device, suppress RARE_PORT for that device.
  - If dst_ip is allowlisted, suppress all scoring (optional toggle).

UI:
- On host page: “Allowlist this ASN” / “Allowlist this org” / “Suppress NO_RDNS for this org”
- On connection row: “Allowlist this port for this device”

Tests:
- allowlist suppresses intended codes and leaves others intact

---

## Step 27 — Investigation UX upgrades (host page + drilldowns)
Add to per-host page:
- “Show connections from device X” (filter links)
- “Show all hosts in same ASN” (search link)
- “Show all hosts with same rDNS suffix” (search link)
- Notes field on RemoteHost:
  - remote_hosts.notes (text, nullable)
- Mark known good / suspicious:
  - remote_hosts.tag (string: "unknown"|"known_good"|"suspicious")

Add copy buttons (pure HTML):
- copy IP, copy org, copy ASN

Optional:
- “Generate nftables block rule” (display-only):
  - Example: `add rule inet filter output ip daddr <ip> drop`
  - Make it obvious it is NOT applied automatically.

---

## Step 28 — Review workflow: “Anomalies” panel + timeline
- Add a small “Recent hits (last 1h)” panel on dashboard.
- Clicking a hit goes to /anomalies with that hit expanded.
- Add acknowledge feature (optional):
  - anomaly_hits.acknowledged_at
  - anomaly_hits.ack_notes

---

## Step 29 — Performance + indexes (must do)
Add/verify indexes:
- remote_hosts(last_seen_at), remote_hosts(first_seen_at)
- connections(last_seen_at), connections(anomaly_score)
- anomaly_hits(occurred_at), anomaly_hits(score), anomaly_hits(dst_ip)
- remote_host_ports(remote_host_id, dst_port), remote_host_ports(last_seen_at)
- devices(ip), devices(name)

Add a safety cap:
- default result limit 200 with pagination.

Tests:
- request specs ensure search endpoints respond fast on seeded data (basic sanity)

---

## Deliverables
- [ ] /search/hosts, /search/connections, /search/anomalies with filters + sorting
- [ ] saved_queries CRUD + UI load/save
- [ ] remote_host_ports table + ingest integration + host page ports list
- [ ] PORT_SCAN_LIKE fixed (requires unique ports + unique dst ips + top_port_share)
- [ ] allowlist_rules + suppression_rules + scorer integration
- [ ] host page drilldowns + notes/tagging
- [ ] recent anomalies panel + (optional) acknowledge
- [ ] indexes + pagination
- [ ] tests for core logic and filters
- [ ] show `git diff --stat` before finishing; revert unrelated file edits

