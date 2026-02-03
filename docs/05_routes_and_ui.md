# Routes + UI behavior

## Pages
- GET `/` Dashboard
  - Live table of active outbound connections (sorted by bytes desc default)
  - Filters: src_ip, dst_ip, dst_port, proto, "new only", "seen before only"
  - Summary tiles: total active conns, total bytes (sum), loadavg, interface tx/rx rates (optional)

## API endpoints (internal)
- GET `/connections.json`
  - params: src_ip, dst_ip, dst_port, proto, q
  - returns active connections list

- GET `/metrics.json`
  - returns system metrics (load, mem, disk, iface stats)

## Live update mechanism
Option A (recommended): Turbo Streams
- Collector broadcasts updates to a stream `connections`
- Dashboard subscribes and updates rows + summary

Option B: polling
- JS fetch every 1s and rerender (works but less elegant)

## “Seen before”
In each connection row:
- dst_ip links to a host detail page (optional later)
- show a badge:
  - NEW if remote_hosts.first_seen_at within last 60s
  - SEEN if older
