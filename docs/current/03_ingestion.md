# Current Ingestion Model

The product currently supports two ingestion paths.

## 1. Agent-driven ingestion

This is the main operational path.

### Event types

The agent sends:

- `flow`
- `dns_response`
- `heartbeat`

via:

- `POST /api/v1/netmon/events/batch`

### Flow ingestion

`Netmon::AgentIngest.ingest_flow!` currently does the following:

1. normalize IPs, ports, protocol, counters, and timestamps
2. upsert `Device`
3. upsert `RemoteHost`
4. enrich `RemoteHost` with rDNS/WHOIS if stale
5. upsert `Connection`
6. compute counter deltas
7. correlate DNS to the connection if needed
8. score the connection when appropriate
9. update `remote_host_domains` if DNS correlation matched
10. update `device_minutes`
11. update `remote_host_minutes`
12. update `remote_host_ports`

### DNS ingestion

`Netmon::Dns::IngestEvent` stores:

- `dns_events`
- `dns_event_answers`

It also backfills matching recent connections when DNS arrives after the flow row.

### Heartbeats

Heartbeats mark collector freshness and drive stale-collector UI indicators.

## 2. Snapshot-driven ingestion

This exists as a Rails-native fallback mode.

Primary tasks:

- `rake netmon:ingest_once`
- `rake netmon:ingest_loop`

Core code:

- `Conntrack::Snapshot`
- `Conntrack::Parser`
- `Netmon::ReconcileSnapshot`
- `Netmon::Daemon`

This mode:

- reads conntrack snapshot output
- filters outbound flows
- upserts devices, remote hosts, and connections
- computes rollups
- emits anomaly hits/incidents

## Outbound Selection Model

Selection is IP/subnet based, not interface based.

Outbound traffic means:

- source is in configured LAN subnets
- destination is not in excluded private/local ranges

This rule is shared conceptually across both snapshot and agent approaches.

## DNS Correlation Model

Correlation prefers:

1. direct A/AAAA answer matches for the same client IP
2. recent PTR-derived fallback matches

The system keeps:

- per-connection `last_domain`
- per-remote-host domain history in `remote_host_domains`

## NFLOG Support

The Go agent can also read NFLOG groups for dropped traffic visibility. That data path is agent-side and complements conntrack rather than replacing it.

## Retention

Current cleanup tasks include:

- `rake netmon:cleanup`
- `rake netmon:dns_prune`

The app keeps summarized state longer than raw DNS telemetry.
