# CODEX_NEXT_AGENT.md

Repo: https://github.com/SafeAF/network_monitor

Goal: Build a Go router agent (Debian) that exports:

- conntrack flow lifecycle telemetry
- firewall drop telemetry (iptables NFLOG)
- DNS cross-referencing (dnsmasq log parsing)
- ships events to a Rails netmon API (no direct Postgres from router for now)

Decisions / constraints:

- Agent lives at: `network_monitor/netmon_agent/`
- Rails app stays at: `network_monitor/netmon/`
- Router interfaces:
  - WAN: `enp2s0`
  - LAN: `enp3s0`
- Router and server are on the same LAN (`enp3s0`), so agent will call Rails over LAN.
- DNS queries are logged by dnsmasq to: `/var/log/dnsmasq.log`
- Out of scope (for now): port-scan detection, separate Postgres ingest, DHCP logging

---

## 0) Deliverables

### 0.1 New directories/files

Create:


netmon_agent/
cmd/netmon_agent/
main.go
internal/
config/
config.go
httpclient/
client.go
nflog/
nflog.go
parse.go
conntrack/
conntrack.go
parse.go
dns/
dnsmasq_tail.go
parse.go
correlate.go
spool/
spool.go
metrics/
metrics.go
util/
ring.go
bounded_queue.go
deploy/
systemd/netmon-agent.service
iptables/netmon-nflog.rules.v4
docs/
AGENT_SETUP.md
EVENT_SCHEMA.md
IPTABLES_NFLOG.md


### 0.2 Rails API endpoint

Add a minimal ingest endpoint in the Rails netmon app, with auth:

- `POST /api/v1/netmon/events/batch`

It accepts a batch of events (mixed types) as JSON and returns:

- `{ accepted: N, rejected: M }`

### 0.3 Event types shipped to Rails

- `firewall_drop` (from NFLOG)
- `flow` (from conntrack NEW/DESTROY summaries)
- `dns_bucket` (aggregated DNS activity)
- `host_identity` (best-effort IP ↔ observed DNS name set)

---

## 1) Operational safety (DoS resistance)

This agent must not become a DoS vector.

### 1.1 Firewall-side limits (required)

- NFLOG rules must include `hashlimit` (per-source throttling) and/or `limit`.
- Log only NEW attempts:
  - TCP: SYN + ctstate NEW
  - UDP: ctstate NEW (optional; keep tighter limits)

### 1.2 Agent-side limits (required)

- Every pipeline uses bounded queues.
- When queues fill, drop events and increment metrics.
- No unbounded maps/sets for correlation. Use capped structures (LRU/ring).
- DNS parsing is aggregation-first; avoid emitting per-query events by default.

### 1.3 Transport robustness (required)

- HTTP batching + backoff.
- If Rails is down, buffer to a bounded on-disk spool OR drop with metrics.
  - For this phase: implement a small spool (example: cap total to 50MB) then drop beyond cap.

### 1.4 Observability (required)

Expose Prometheus metrics endpoint (LAN-only), default:

- `127.0.0.1:9109`

Include queue depth, dropped counts, http errors, parse errors, and spool size.

---

## 2) iptables NFLOG rules (router)

Reduced scope: only observe dropped inbound and forwarded attempts. No scan detection logic yet.

Assumptions:

- WAN interface: `enp2s0`
- LAN interface: `enp3s0`
- You already have a firewall ruleset. We add dedicated chains and jump to them right before final drops.

### 2.1 Create chains

- `NETMON_INPUT_DROPLOG`
- `NETMON_FORWARD_DROPLOG`

### 2.2 INPUT chain (drops to router)

Log TCP SYN and UDP NEW attempts on WAN that would be dropped.

Example chain contents:

```bash
# TCP SYN attempts to router on WAN (rate-limited per source IP)
iptables -A NETMON_INPUT_DROPLOG -i enp2s0 -p tcp --syn -m conntrack --ctstate NEW \
  -m hashlimit --hashlimit-name nm_in_syn --hashlimit-mode srcip \
  --hashlimit 5/second --hashlimit-burst 20 \
  -j NFLOG --nflog-group 10 --nflog-prefix "DROP_IN_SYN "

iptables -A NETMON_INPUT_DROPLOG -i enp2s0 -p tcp --syn -m conntrack --ctstate NEW -j DROP

# UDP NEW to router on WAN (tighter; optional)
iptables -A NETMON_INPUT_DROPLOG -i enp2s0 -p udp -m conntrack --ctstate NEW \
  -m hashlimit --hashlimit-name nm_in_udp --hashlimit-mode srcip \
  --hashlimit 2/second --hashlimit-burst 10 \
  -j NFLOG --nflog-group 10 --nflog-prefix "DROP_IN_UDP "

iptables -A NETMON_INPUT_DROPLOG -i enp2s0 -p udp -m conntrack --ctstate NEW -j DROP

Integrate by jumping to this chain just before your final INPUT drop, for packets you intend to drop:

# near end of INPUT chain, before your default drop (placement matters)
iptables -A INPUT -j NETMON_INPUT_DROPLOG
2.3 FORWARD chain (WAN -> LAN drops)

Log unsolicited inbound to internal hosts that would be dropped.

iptables -A NETMON_FORWARD_DROPLOG -i enp2s0 -o enp3s0 -p tcp --syn -m conntrack --ctstate NEW \
  -m hashlimit --hashlimit-name nm_fwd_syn --hashlimit-mode srcip \
  --hashlimit 5/second --hashlimit-burst 20 \
  -j NFLOG --nflog-group 11 --nflog-prefix "DROP_FWD_SYN "

iptables -A NETMON_FORWARD_DROPLOG -i enp2s0 -o enp3s0 -p tcp --syn -m conntrack --ctstate NEW -j DROP

Integrate by jumping near end of FORWARD chain, before your final drop for WAN->LAN traffic you intend to drop:

iptables -A FORWARD -j NETMON_FORWARD_DROPLOG

Notes:

Put these jumps only where they won’t catch traffic you already ACCEPT earlier.

If you have explicit DROP rules, insert NFLOG immediately before those specific DROPs instead of a blanket end-of-chain jump.

3) Event schema shipped to Rails

Define a single batch format.

3.1 Request: POST /api/v1/netmon/events/batch

Headers:

Authorization: Bearer <shared-secret>

Content-Type: application/json

Body:

{
  "router_id": "router-01",
  "sent_at": "2026-02-20T14:21:33Z",
  "events": [
    { "type": "firewall_drop", "ts": "2026-02-20T14:21:33.123Z", "data": { } },
    { "type": "flow",          "ts": "2026-02-20T14:21:34.000Z", "data": { } },
    { "type": "dns_bucket",    "ts": "2026-02-20T14:22:00.000Z", "data": { } },
    { "type": "host_identity", "ts": "2026-02-20T14:22:00.000Z", "data": { } }
  ]
}
3.2 Event: firewall_drop

Derived from NFLOG groups:

group 10: INPUT drops

group 11: FORWARD drops

Example:

{
  "type": "firewall_drop",
  "ts": "2026-02-20T14:21:33.123Z",
  "data": {
    "hook": "INPUT",
    "rule_tag": "DROP_IN_SYN",
    "nflog_group": 10,
    "if_in": "enp2s0",
    "if_out": null,
    "src_ip": "203.0.113.9",
    "dst_ip": "198.51.100.2",
    "src_port": 51512,
    "dst_port": 22,
    "l4proto": 6,
    "tcp_syn": true
  }
}
3.3 Event: flow (conntrack summary)

Emit at least DESTROY summaries (totals). NEW events are optional and config-gated.

{
  "type": "flow",
  "ts": "2026-02-20T14:21:34.000Z",
  "data": {
    "event": "DESTROY",
    "src_ip": "192.168.1.50",
    "dst_ip": "142.250.72.46",
    "src_port": 51422,
    "dst_port": 443,
    "l4proto": 6,
    "dir": "OUT",
    "bytes_orig": 18233,
    "bytes_reply": 923112,
    "packets_orig": 122,
    "packets_reply": 140,
    "first_seen": "2026-02-20T14:21:00Z",
    "last_seen": "2026-02-20T14:21:34Z"
  }
}
3.4 Event: dns_bucket (aggregated DNS activity)

Default behavior: aggregate into minute buckets per (client_ip, qtype, qname_hash).

{
  "type": "dns_bucket",
  "ts": "2026-02-20T14:22:00.000Z",
  "data": {
    "bucket_start": "2026-02-20T14:21:00.000Z",
    "client_ip": "192.168.1.50",
    "qtype": "A",
    "qname_hash": "b64:0p6f...==",
    "count": 37,
    "nxdomain": 2
  }
}

Policy:

Hash qname by default (privacy + size control).

Cap per-client distinct qnames per bucket (example: 200). Over cap, roll into qname_hash="other".

3.5 Event: host_identity (best-effort, from dnsmasq log)

This is not DHCP identity. It’s a lightweight mapping of a LAN client to recent DNS names it queried.

Emit once per minute per active LAN client.

{
  "type": "host_identity",
  "ts": "2026-02-20T14:22:00.000Z",
  "data": {
    "ip": "192.168.1.50",
    "last_seen": "2026-02-20T14:21:55.000Z",
    "recent_qname_hashes": ["b64:...", "b64:..."]
  }
}
4) DNS cross-referencing plan (dnsmasq.log)

Input:

/var/log/dnsmasq.log

Implement:

Tail the file with rotation handling (inode changes).

Parse lines into:

timestamp

verb/action (query/forwarded/reply/cached/nxdomain)

client IP (when present)

qname

qtype

Update minute buckets for dns_bucket emission.

Maintain a bounded per-client cache for enrichment:

client_ip -> last_seen, recent_qname_hashes (ring, cap 200), per-minute counters

Cross-reference usage:

Enrich flow and firewall_drop events when the involved LAN IP is present in the DNS cache.

Enrichment should be optional; do not block event shipping if DNS fails.

5) Go agent build plan (implementation order)
Step A: scaffold + config

Create netmon_agent/ module.

Add config loader (/etc/netmon-agent/config.yaml) with:

router_id

rails_base_url (example: http://<server_lan_ip>:3000)

auth_token

nflog_groups (10, 11)

dnsmasq_log_path (/var/log/dnsmasq.log)

batching and queue sizes

qname hashing settings (salted)

metrics bind address

Step B: HTTP batch client

Build internal/httpclient:

event accumulator

flush every 1s OR on 250 events

retries with exponential backoff

on persistent failure:

write batches to spool

Step C: bounded on-disk spool

Build internal/spool:

directory: /var/lib/netmon-agent/spool/

store newline-delimited JSON batches or one-batch-per-file segments

cap total size (default 50MB)

replay oldest first when HTTP recovers

metrics: spool_bytes, spool_batches, spool_dropped_batches_total

Step D: NFLOG ingestion

Build internal/nflog:

subscribe groups 10 and 11 via netlink

parse:

prefix into rule_tag

5-tuple (src/dst ip, ports, proto)

ifindex -> ifname

emit firewall_drop events

bounded channel between reader and batcher

Step E: conntrack ingestion

Build internal/conntrack:

subscribe to ctnetlink events

emit only DESTROY summaries by default

optionally emit NEW for debugging (config)

compute:

direction (IN|OUT|FWD) using interface hints and LAN subnet config (optional)

bytes/packets totals

Step F: DNS tail + aggregation

Build internal/dns:

tail dnsmasq log with rotation handling

parse robustly

aggregate to minute buckets

emit dns_bucket events

maintain per-client ring of recent qname hashes and last_seen

emit host_identity once/min/client

Step G: enrichment (optional)

Add enrichment for LAN client IPs:

attach dns_context to flow events where src_ip (LAN) exists in cache

attach dns_context to firewall_drop events where dst_ip is LAN and exists in cache

Keep enrichment compact, bounded, and optional.

Step H: metrics endpoint

Expose /metrics:

Required counters/gauges:

nflog_events_total{group,tag}

nflog_parse_errors_total

conntrack_destroy_total

conntrack_parse_errors_total

dns_lines_total

dns_parse_errors_total

dns_buckets_emitted_total

queue_depth{stream}

events_dropped_local_total{stream}

http_batches_sent_total

http_send_errors_total{code}

spool_bytes

spool_batches

spool_dropped_batches_total

Step I: systemd unit

Create deploy/systemd/netmon-agent.service:

restart always

set working dir

create required dirs via ExecStartPre

start as root initially (netlink access), harden later

6) Rails netmon API (minimal)
6.1 Auth

Start with:

Bearer token in Authorization header

Later option: HMAC signature (not required now).

6.2 Storage

For now store events in Rails DB tables (simple append). You can normalize later.

Create tables (or JSONB event log):

netmon_events with event_type, ts, router_id, data jsonb

This avoids schema churn during early agent bring-up.

7) Test plan
7.1 NFLOG test

Apply iptables NFLOG rules.

From outside (or a VPS), attempt TCP connect to a closed port on router WAN IP.

Confirm agent emits firewall_drop with DROP_IN_SYN and group 10.

7.2 FORWARD test

Attempt inbound to a LAN host that is not allowed/forwarded.

Confirm group 11 events with DROP_FWD_SYN.

7.3 DNS test

Generate DNS queries from a LAN client.

Confirm agent emits dns_bucket events.

Confirm host_identity emits per active client.

Confirm enrichment appears on flow/drop events when applicable.

7.4 Failure + backpressure test

Stop Rails.

Generate NFLOG activity.

Confirm:

queues cap

spool caps

drops are counted, not unbounded growth

agent stays alive

8) Definition of Done

Agent runs on router as a systemd service.

Receives NFLOG events for INPUT (group 10) and FORWARD (group 11).

Receives conntrack DESTROY summaries.

Tails dnsmasq log and emits aggregated DNS buckets + host identity.

Batches and POSTs to Rails ingest endpoint reliably.

Has bounded queues and a bounded spool.

Exposes Prometheus metrics.

Docs exist:

docs/AGENT_SETUP.md with install + verification steps