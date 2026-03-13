# CODEX_NEXT_DNS.md — DNS Fingerprinting via Go Agent Integration

## Goal
Integrate DNS telemetry from the existing Go agent into NetMon so remote hosts and connections can be correlated to domains queried by LAN devices.

Do not change conntrack ingestion logic. Add DNS as a parallel enrichment pipeline.

## Source of truth
Use `docs/DNS_AGENT_CONTRACT.md`.

## Implementation decisions (locked)
- DNS source on router: `/var/log/dnsmasq.log`
- Transport: existing `/api/v1/netmon/events/batch` as `dns_response` events
- Store full `qname` (no hashing/redaction)
- Defer `remote_host` domain linking until there is a matching connection
- Raw DNS retention window: 30 days

## Step 1 — Add DNS persistence models
Create migrations/models for:

### dns_events
- id
- router_id (string, not null)
- observed_at (datetime, not null)
- client_ip (string, not null)
- qname (string, not null)
- qtype (string, not null)
- rcode (string, nullable)
- resolver (string, nullable)
- answers_json (text, not null, default "[]")
- dedupe_key (string, not null)
- created_at
- updated_at

Indexes:
- observed_at
- client_ip, observed_at
- qname, observed_at
- unique index on dedupe_key

### dns_event_answers
- id
- dns_event_id (fk, not null)
- answer_ip (string, not null)
- answer_type (string, not null)  # A or AAAA
- created_at
- updated_at

Indexes:
- answer_ip, created_at
- dns_event_id

### remote_host_domains
- id
- remote_host_id (fk, not null)
- domain (string, not null)
- first_seen_at (datetime, not null)
- last_seen_at (datetime, not null)
- seen_count (int, default 0, not null)
- last_device_ip (string, nullable)
- created_at
- updated_at

Unique index:
- remote_host_id, domain

## Step 2 — Add DNS ingest service (API event path)
Implement:
- `Netmon::Dns::IngestEvent.call(router_id:, data:, ts:)`

Wire it in `Netmon::AgentIngest.ingest_event!` under:
- `event_type == "dns_response"`

Behavior:
- validate required fields (`client_ip`, `qname`, `qtype`)
- parse `answers` array
- generate `dedupe_key` from normalized payload
- insert one `dns_events` row (idempotent by `dedupe_key`)
- insert `dns_event_answers` rows for A/AAAA only
- log and skip malformed payloads

Important:
- DNS ingest failure must not block flow ingestion.

## Step 3 — Add connection-to-domain correlation
Implement:
- `Netmon::Dns::CorrelateConnection.call(connection:)`

Lookup logic:
- match `dns_events.client_ip == connection.src_ip`
- join `dns_event_answers.answer_ip == connection.dst_ip`
- window: recent events (start with 10 minutes, configurable)
- best match: most recent `observed_at`

Store on connection:
- `connections.last_domain` (string, nullable)
- `connections.last_domain_observed_at` (datetime, nullable)
- optional `connections.last_domain_confidence` (integer/float)

If no match, leave blank.

## Step 4 — Defer remote_host domain linking until connection match
When a connection gets a DNS match:
- use that connection’s existing `remote_host` (`dst_ip`)
- upsert `remote_host_domains` for:
  - remote_host_id
  - domain = matched qname
- update:
  - first_seen_at / last_seen_at
  - seen_count += 1
  - last_device_ip = connection.src_ip

Do not create `remote_hosts` from DNS answers alone.

## Step 5 — UI and search
### Remote host page
Show:
- recent associated domains
- counts
- first_seen / last_seen for each domain

### Connections table
Optional column:
- domain (`last_domain`)

### Search
Extend `/search/hosts` with:
- `domain=` substring filter
via join on `remote_host_domains`

## Step 6 — Retention
Add cleanup task/job:
- delete raw `dns_events` and `dns_event_answers` older than 30 days
- keep `remote_host_domains` aggregate history

Suggested task:
- `netmon:dns_prune`

## Step 7 — Tests
Add specs for:
- `dns_response` API ingest path
- idempotent insert via dedupe key
- malformed payload tolerance
- answer normalization (A/AAAA extraction)
- connection correlation picks most recent matching dns_event
- remote_host_domains only updates when a matching connection exists
- retention job removes >30-day raw DNS rows

## Constraints
- No new external dependencies unless required
- Do not block conntrack ingest on DNS ingest
- DNS ingest should be separate from flow ingest path
- Keep it replay-safe and idempotent
