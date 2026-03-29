# Current Architecture

## System Overview

The current system is a Rails app plus an optional but preferred Go router agent.

### Rails app

The Rails app is responsible for:

- persisting flow, DNS, anomaly, and rollup data
- correlating DNS to flows
- scoring connections
- rendering the operator UI
- exposing JSON endpoints used by the dashboard

### Go agent

The Go agent is responsible for:

- tailing `dnsmasq` logs
- reading conntrack events
- reading NFLOG events
- batching events to Rails
- buffering and replaying events via a local spool on failure

## Data Flow

### Agent-driven path

1. Router agent reads conntrack and dnsmasq/NFLOG data.
2. Agent normalizes events into:
   - `flow`
   - `dns_response`
   - `heartbeat`
3. Agent batches events to:
   - `POST /api/v1/netmon/events/batch`
4. Rails stores raw events in `netmon_events`.
5. Rails runs ingest logic:
   - flow upserts
   - DNS event persistence
   - DNS-to-flow correlation
   - anomaly scoring
   - per-minute rollup updates
6. UI pages and JSON endpoints query the normalized tables.

### Snapshot path

1. Rails invokes conntrack snapshot parsing.
2. `Netmon::ReconcileSnapshot` filters outbound flows.
3. Rails upserts devices, remote hosts, connections, rollups, and anomaly hits.

Snapshot mode still exists, but the agent-driven flow is the richer architecture.

## Key Runtime Components

### Web/UI controllers

- `DashboardController`
- `ConnectionsController`
- `AnomaliesController`
- `IncidentsController`
- `RemoteHostsController`
- `SearchController`
- `MetricsController`
- `SystemMetricsController`

### Ingest and scoring

- `Api::V1::Netmon::EventsController`
- `Netmon::AgentIngest`
- `Netmon::Dns::*`
- `Netmon::Anomaly::DeviceStats`
- `Netmon::Anomaly::Scorer`

### Snapshot ingest

- `Conntrack::Parser`
- `Conntrack::Snapshot`
- `Netmon::ReconcileSnapshot`
- `Netmon::Daemon`

## Storage Model

The app stores both raw and normalized data.

### Raw-ish event layer

- `netmon_events`
- `dns_events`
- `dns_event_answers`

### Investigation layer

- `devices`
- `remote_hosts`
- `connections`
- `remote_host_ports`
- `remote_host_domains`

### Rollups and baselines

- `device_minutes`
- `remote_host_minutes`
- `metric_samples`
- `system_minutes`
- `device_baselines`

### Triage and workflow

- `anomaly_hits`
- `incidents`
- `allowlist_rules`
- `suppression_rules`
- `saved_queries`

## Performance Reality

In simple deployments, UI requests and ingest requests share the same Puma process and the same SQLite database. That means:

- ingest slowness directly affects page latency
- logging overhead matters more than in a typical production deployment
- repeated per-event work must be minimized

## Current Tradeoffs

- SQLite keeps deployment simple, but raises contention and scaling limits
- running in `development` simplifies local/LAN operation, but can add avoidable overhead
- the current app is optimized for practicality and operator visibility over architectural purity
