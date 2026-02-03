# Architecture

## High-level
Rails app provides a web UI. A background collector reads conntrack data from the router and stores:
- a rolling set of "active connections" (fast lookup for UI)
- a table of "remote hosts" with first_seen/last_seen
- optional periodic snapshots for "bytes delta" rates

UI updates via Turbo Streams (ActionCable/WebSocket) or periodic polling JSON.

## Why conntrack
Linux netfilter conntrack already sees NATed flows and includes counters (packets/bytes) per flow entry.
We will use conntrack userspace tooling and/or /proc filesystem.

Preferred: `conntrack` tool (conntrack-tools)
- Event stream: `conntrack -E` (NEW/UPDATE/DESTROY)
- Snapshot: `conntrack -L` for periodic reconciliation

Fallback: `/proc/net/nf_conntrack` or `/proc/net/ip_conntrack`
- Parse lines for flows + counters; depends on kernel config and permissions.

## Components

### 1) Collector (Ruby service in-app)
A Ruby process runs alongside Rails:
- Consumes conntrack events to detect NEW connections fast.
- Periodically reconciles active list via snapshots to get accurate counters.

Implementation approach:
- Spawn `conntrack -E -o timestamp,extended` and parse stdout line-by-line.
- Every 2s (configurable), run `conntrack -L -o extended` and parse to rebuild a map of active outbound connections and counters.

Reason: event stream is great for "new connection now", snapshots are better for "bytes/packets now".

### 2) Storage (SQLite)
Tables:
- `connections` (current active list, upsert by 5-tuple key)
- `remote_hosts` (dst_ip identity, first_seen_at, last_seen_at, optional metadata)
- optionally `connection_samples` for short history (last N minutes)

### 3) UI (Rails + Hotwire)
- Dashboard controller renders initial page.
- Live updates delivered via Turbo Streams broadcasting updated rows and summary stats.
- Filtering/search handled server-side with query params.

## Security model
- App binds to 10.0.0.1 (LAN only), not public WAN.
- Optional basic auth.
- Collector runs with required permissions to read conntrack (usually root or CAP_NET_ADMIN). Prefer:
  - run collector under systemd with AmbientCapabilities=CAP_NET_ADMIN
  - keep Rails web process unprivileged if possible.

## Interfaces
We explicitly label:
- LAN interface: enp3s0 (10.0.0.1/24)
- WAN interface: enp2s0 (135.131.124.247/21)

Outbound definition uses IP ranges, not interface direction, to avoid NAT ambiguity.
