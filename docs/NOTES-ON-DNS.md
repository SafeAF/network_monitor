# Notes on DNS Integration (Pre-Implementation)

## Scope reviewed
- `docs/DNS_AGENT_CONTRACT.md`
- `docs/CODEX_NEXT_DNS.md`

Note: your request referenced `docs/DNSAGENT_CONTRACT.md`; the file in repo is `docs/DNS_AGENT_CONTRACT.md`.

## Understanding check
I understand the intended feature set:
- ingest DNS response telemetry
- persist raw DNS events
- map domains to remote hosts
- correlate connection rows to likely domains
- surface DNS context in host/connection UI and search

The feature direction is good and useful for this project.

## Fit with current project architecture
Current architecture is:
- Go agent on router sends events to Rails over `POST /api/v1/netmon/events/batch`
- Rails stores raw events in `netmon_events` and enriches `connections`/`remote_hosts` via `Netmon::AgentIngest`

The proposed DNS design in `CODEX_NEXT_DNS.md` mostly fits, but one key part does not:
- The contract assumes Rails reads `tmp/dns_events.jsonl` locally.
- In this project, DNS is produced on the router, not on the Rails host.
- A local Rails file tailer is not a reliable transport boundary for this deployment model.

## Potential issues and remedies

### 1) Transport mismatch (highest risk)
- Issue: JSONL file ingestion from Rails local disk does not match agent-on-router deployment.
- Remedy: keep existing HTTP batch path as primary transport. Add a new event type (for example `dns_response`) sent by agent in `/events/batch`. Keep router-local spool for reliability.

### 2) Query performance for IP-in-answers matching
- Issue: storing `answers_json` as text and querying “contains dst_ip” will become slow and brittle.
- Remedy: add normalized answer table (for example `dns_event_answers`) with indexed `answer_ip`.
Columns:
- `dns_event_id`
- `answer_ip`
- `answer_type`
- indexes on `(answer_ip, observed_at)` and `(dns_event_id)`

### 3) Duplicate ingestion / replay safety
- Issue: retries/replays can duplicate DNS rows and inflate counts.
- Remedy: add idempotency key and unique index.
Example key:
- hash of `observed_at + client_ip + qname + qtype + sorted(answer_ips) + resolver`

### 4) Offset file reliability
- Issue: `tmp/dns_events.offset` is fragile across deploy/restart and multi-process Rails.
- Remedy: if file tailing is kept at all, store offsets in DB with row-level locking. Prefer avoiding file tailing and ingest inline from API.

### 5) Data growth and retention
- Issue: one row per DNS response can grow very fast.
- Remedy:
- retention policy (for example raw `dns_events` 7-30 days)
- periodic prune job
- keep long-lived aggregates in `remote_host_domains`

### 6) Correlation quality and false attribution
- Issue: “most recent DNS event in 30m” can misattribute CDN/shared IPs.
- Remedy:
- tighter default window (for example 2-10 minutes)
- score-based match: same `client_ip` + closest timestamp + exact answer IP
- store confidence on connection correlation

### 7) DNS-only remote hosts
- Issue: creating `remote_hosts` from DNS answers alone can create many noisy hosts never connected.
- Remedy:
- either mark DNS-only hosts with a tag/source field
- or defer remote_host creation until a matching connection appears

### 8) Privacy and sensitivity
- Issue: full `qname` storage is sensitive and can include user-identifying domains.
- Remedy:
- config toggle for plaintext vs hashed qname
- optional redaction rules
- document retention and access policy

### 9) Search query complexity
- Issue: joining `remote_host_domains` into host search can break count/distinct pagination if not done carefully.
- Remedy:
- keep search in query object layer
- use `distinct` host IDs for counts
- add request specs for pagination/count correctness

### 10) Non-blocking ingest guarantee
- Issue: DNS processing should not slow flow ingest.
- Remedy:
- handle `dns_response` as separate branch in `Netmon::AgentIngest`
- keep work bounded; do minimal writes inline
- push expensive enrichment to async job if needed

## Recommended adjustments before implementation
1. Update contract transport from “Rails tails local JSONL” to “agent sends DNS events over existing batch API”.
2. Keep `dns_events`, but add normalized `dns_event_answers` for indexed correlation.
3. Define idempotency key + unique index up front.
4. Define retention window for `dns_events` now (not later).
5. Define correlation confidence and store it alongside `connections.last_domain`.
6. Decide now whether DNS-only remote hosts are allowed or deferred.

## Verdict
The DNS enrichment plan makes sense for NetMon and should improve host attribution significantly.

Before coding, transport and indexing should be adjusted as above; otherwise the implementation will work in small tests but struggle in real router traffic and long-running deployments.

## Project owner decisions (confirmed)
- DNS source path is `/var/log/dnsmasq.log`.
- Keep full `qname` storage (single-user environment).
- Defer `remote_host` domain creation/linking until there is a matching connection.
- Raw DNS retention is 30 days.
