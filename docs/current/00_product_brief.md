# NetMon Current Product Brief

NetMon is a LAN-focused network monitoring system made of two parts:

- a Rails web app in `netmon/`
- a Go router agent in `netmon_agent/`

The current product observes outbound network activity, correlates DNS lookups to flows, scores suspicious behavior, and presents the result in an investigation-oriented web UI.

## What It Does

- Collects flow activity from conntrack-derived events
- Correlates DNS responses from `dnsmasq` logs to remote IPs
- Tracks remote hosts, ports, domains, and per-minute rollups
- Scores connections and emits anomaly hits and grouped incidents
- Shows live and recent activity in a dense web UI
- Exposes system and interface metrics for the host running the Rails app

## Main User Workflows

- See current active connections on `/`
- Review anomalies on `/anomalies`
- Review grouped incidents on `/incidents`
- Investigate remote hosts on `/remote_hosts/:ip`
- Search hosts, connections, and anomalies under `/search`
- Maintain allowlist and suppression rules to reduce noise

## Current Deployment Shape

There are two supported operating modes:

- Rails-only snapshot mode:
  - Rails reads conntrack snapshots directly with rake tasks
- Agent-driven mode:
  - the Go agent runs on the router
  - it sends batched `flow`, `dns_response`, and `heartbeat` events to Rails

Agent-driven mode is the more complete and currently more important path because it supports:

- DNS correlation
- conntrack `NEW` and `DESTROY` events
- NFLOG-based drop visibility
- durable spool/retry behavior

## Important Constraints

- Current deployments often use SQLite
- Current field deployments may run Rails in `development` for LAN-only use
- Performance depends heavily on the ingest path because the UI and ingest share the same app server process in simple deployments

## Non-goals

- DPI / packet payload inspection
- endpoint process attribution
- enterprise-scale multi-tenant architecture

## Canonical References

- Architecture: `docs/current/01_architecture.md`
- Data model: `docs/current/02_data_model.md`
- Ingestion: `docs/current/03_ingestion.md`
- Operations: `docs/current/06_operations.md`
- Agent deployment: `docs/current/07_agent_deployment.md`
