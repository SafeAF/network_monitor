# Architecture (NetMon)

## Purpose
NetMon is a LAN-scoped Rails app that observes outbound network activity using Linux netfilter conntrack and presents:
- active connections (near real-time)
- per-remote-host pages (history + enrichment)
- anomaly scoring + review/ack workflow
- incidents (grouped anomaly bursts)
- baseline-driven metrics/graphs for trend and deviation

This is designed to run on a router (or workstation during dev). It assumes a NAT environment where conntrack provides the authoritative flow view.

---

## Data sources

### Conntrack (primary)
NetMon ingests snapshots from conntrack to observe flows and counters (bytes/packets). We rely on:
- `conntrack -L` (and/or `/proc/net/nf_conntrack`) for snapshot state
- conntrack accounting enabled via: `net.netfilter.nf_conntrack_acct=1`

We treat outbound connections as those whose **src_ip is a known LAN device (10.0.0.0/24)** and dst_ip is outside LAN.

### Enrichment (best-effort)
- rDNS lookups (rate-limited)
- WHOIS/ASN org string (currently via whois-derived fields; may later move to offline ASN DB)
- traceroute endpoint per remote host (JSON)

---

## Core entities (DB model)

### Devices (LAN identities)
`devices` keyed by `ip` (example: 10.0.0.20) with optional friendly `name` and `notes`.
Used to label traffic sources and drive per-device baselines.

### Remote hosts (remote identities)
`remote_hosts` keyed by `ip` (remote dst_ip). Tracks:
- first_seen_at / last_seen_at
- rDNS + WHOIS + ASN fields
- tag + notes for manual triage

“Seen before” is remote-host based (dst_ip), not connection-based.

### Connections (active-ish flows)
`connections` represent current/last-seen flows keyed by the stable 5-tuple:
(proto, src_ip, src_port, dst_ip, dst_port)
Tracks:
- bytes/packets uplink/downlink
- first_seen_at / last_seen_at
- delta fields (last_* + last_delta_at) for rate-ish behavior
- per-connection anomaly_score + anomaly_reasons_json for current-table display

### Metrics rollups
NetMon keeps time-bucket rollups for trend and baselines:
- `device_minutes`: per-device per-minute buckets (conn_count, bytes, new dst, unique ports/asns, rare ports, etc.)
- `device_baselines`: rolling p95 baselines (uplink per min, conn/min, new dst/10m, unique ports/10m)
- `remote_host_minutes`: per-remote-host per-minute bytes/conn_count
- `remote_host_ports`: (remote_host_id, dst_port) first/last seen + seen_count to support “rare port” logic
- `metric_samples`: global dashboard samples for charts (new dst/10m, unique ports/10m, uplink/10m, new asns/1h, baseline p95 comparisons)

### Anomalies and incidents (review workflow)
`anomaly_hits` are persisted triggers with:
- occurred_at, device_id, dst_ip/dst_port/proto
- score, reasons_json, fingerprint
- ack state + notes
- incident linkage (incident_id)
- alertable boolean (policy-driven)

`incidents` group bursts by fingerprint (time window based grouping):
- fingerprint + device/dst fields
- codes_csv, first/last seen, count, max_score
- ack fields

### Rules/config
- `allowlist_rules`: user-supplied “this is expected” rules (per-device optional)
- `suppression_rules`: suppress specific codes/kinds/values (per-device optional)
- `saved_queries`: stored filter presets for investigation UX

---

## Ingest + scoring pipeline (high-level)

1) Snapshot acquisition
- A scheduled task runs `conntrack -L` and parses entries.
- Filtering identifies outbound flows (LAN src -> non-LAN dst).

2) Reconciliation
- Upsert `connections` by 5-tuple.
- Update byte/packet counters and last_seen_at.
- Maintain `devices` and `remote_hosts` last_seen_at and create-on-first-seen.

3) Rollups
- Update per-minute buckets in `device_minutes` and `remote_host_minutes`.
- Update `remote_host_ports` for dst_port first/last/seen_count.
- Produce `metric_samples` for dashboard charting.

4) Scoring
- Compute anomaly codes and score for current connections (table display).
- Persist `anomaly_hits` when triggers fire (with fingerprint).
- Group into `incidents` using fingerprint + windowing.
- Apply suppression/allowlist to reduce noise; set alertable accordingly.

---

## Web UI (server-rendered + JSON endpoints)

### Main routes/pages
- `/` Dashboard (charts, top panels, active connections table)
- `/anomalies` anomalies list + filters + ack
- `/incidents` incidents list; `/incidents/:id` show + ack
- `/remote_hosts` list; `/remote_hosts/:ip` show + edit + traceroute
- `/devices` edit device names/notes
- `/search/*` search across hosts/connections/anomalies
- `/saved_queries` create saved filters
- `/allowlist_rules`, `/suppression_rules` create rules

### JSON endpoints for polling/partials
- `/dashboard/top_panels` (JSON)
- `/connections` (JSON)
- `/metrics`, `/metrics/series` (JSON)

UI is Tailwind-styled and optimized for dense investigation.

---

## Security + deployment assumptions
- Intended to bind to LAN only (router / workstation).
- Conntrack access requires root or capabilities (CAP_NET_ADMIN). Prefer:
  - keep web process unprivileged where possible
  - run ingest task/service with required privileges

---

## Known gaps / future work
- DNS correlation (requires local resolver/logging)
- Offline ASN DB (reduce whois traffic)
- External alert delivery (email/webhook) with anti-spam incident grouping
- Better search UX + saved queries refinements
