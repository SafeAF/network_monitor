# Implementation tasks (Codex checklist)

## 0) Rails app skeleton
- rails new netmon --database=sqlite3 --css=tailwind --javascript=esbuild
- Create models: RemoteHost, Connection
- Add indexes + unique constraints

## 1) Conntrack collector
- Create Ruby service object: Conntrack::Collector
- It should:
  - spawn event reader thread (conntrack -E)
  - run snapshot reconcile loop (conntrack -L) every 2s
  - upsert DB rows
  - on every outbound entry, upsert RemoteHost for orig.dst_ip; do not create per-connection seen markers
  - broadcast Turbo updates (optional at first)

Acceptance:
- Running collector logs NEW outbound connections as they happen.
- DB has rows with src/dst/ports.

## 2) Parser
- Create Conntrack::Parser to parse lines into a struct:
  - proto, src_ip, dst_ip, sport, dport, packets, bytes, state, flags
- Add robust tests with captured sample lines.

Acceptance:
- Parser handles both single-tuple and dual-tuple lines.
- Extracts counters when present.

## 3) Dashboard UI
- Create DashboardController#index
- Tailwind table with filters
- show badges: proto, state, seen-before

Acceptance:
- Open / shows data from DB; filters work.

## 4) Live updates
- Add Turbo Streams broadcasting:
  - on upsert, broadcast replace row partial
  - broadcast summary updates

Acceptance:
- With page open, new connections appear without reload (within 1–2s).

## 5) System metrics
- Create Metrics module reading /proc and /sys
- Endpoint metrics.json
- UI tile updates

Acceptance:
- loadavg and iface bytes update on page.

## 6) Hardening
- Bind server to LAN interface
- Optional basic auth
- systemd unit for collector with CAP_NET_ADMIN

Acceptance:
- Not reachable from WAN; collector runs on boot.
