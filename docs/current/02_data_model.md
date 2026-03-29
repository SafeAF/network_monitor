# Current Data Model

This describes the tables and relationships that matter for the shipped system.

## Devices

Represents LAN identities.

Important fields:

- `ip`
- `name`
- `first_seen_at`
- `last_seen_at`
- `notes`

Used by:

- connection attribution
- anomaly baselines
- UI labeling

## Remote Hosts

Represents remote IPs.

Important fields:

- `ip`
- `first_seen_at`
- `last_seen_at`
- `rdns_name`
- `whois_name`
- `whois_raw_line`
- `whois_asn`
- `tag`
- `notes`

Related tables:

- `remote_host_ports`
- `remote_host_domains`
- `remote_host_minutes`

## Connections

Represents tracked flows keyed by the 5-tuple:

- `proto`
- `src_ip`
- `src_port`
- `dst_ip`
- `dst_port`

Important fields:

- `state`
- `flags`
- `first_seen_at`
- `last_seen_at`
- `uplink_bytes`
- `downlink_bytes`
- `uplink_packets`
- `downlink_packets`
- `last_*` counter fields for delta computation
- `anomaly_score`
- `anomaly_reasons_json`
- `last_domain`
- `last_domain_observed_at`

## DNS Event Tables

### `dns_events`

Stores normalized DNS observations.

Important fields:

- `router_id`
- `observed_at`
- `client_ip`
- `qname`
- `qtype`
- `answers_json`
- `dedupe_key`

### `dns_event_answers`

Stores answer IP rows for correlation.

Important fields:

- `dns_event_id`
- `answer_ip`
- `answer_type`

These tables support:

- direct answer correlation
- PTR fallback correlation
- remote host domain linking

## Remote Host Port History

### `remote_host_ports`

Tracks which destination ports were seen for a remote host.

Important fields:

- `remote_host_id`
- `dst_port`
- `first_seen_at`
- `last_seen_at`
- `seen_count`

## Remote Host Domain History

### `remote_host_domains`

Tracks domains associated with a remote host.

Important fields:

- `remote_host_id`
- `domain`
- `first_seen_at`
- `last_seen_at`
- `last_device_ip`
- `seen_count`

## Rollup Tables

### `device_minutes`

Per-device per-minute rollups.

Used for:

- metrics cards
- baseline computation
- fanout and port-behavior scoring

### `remote_host_minutes`

Per-remote-host per-minute rollups.

Used for:

- top remote hosts panels
- per-host traffic summaries

### `metric_samples`

Time-bucketed global samples for charts.

### `system_minutes`

System and interface metric history used by graph endpoints.

### `device_baselines`

Rolling baseline values used by anomaly scoring.

## Workflow Tables

### `anomaly_hits`

Persisted anomaly detections.

Important fields:

- `occurred_at`
- `device_id`
- `remote_host_id`
- `dst_ip`
- `dst_port`
- `proto`
- `score`
- `summary`
- `reasons_json`
- `fingerprint`
- `alertable`
- `acknowledged_at`
- `ack_notes`
- `incident_id`

### `incidents`

Grouped collections of related anomaly hits.

Important fields:

- `fingerprint`
- `device_id`
- `dst_ip`
- `dst_port`
- `proto`
- `codes_csv`
- `count`
- `max_score`
- `first_seen_at`
- `last_seen_at`
- `acknowledged_at`
- `ack_notes`

## Raw Event Log

### `netmon_events`

Stores raw incoming agent events and some internal event payloads.

This is useful for:

- debugging ingest behavior
- validating agent payloads
- reconstructing recent event flow

## Rule Tables

- `allowlist_rules`
- `suppression_rules`
- `saved_queries`

These support operator workflow rather than telemetry capture.
