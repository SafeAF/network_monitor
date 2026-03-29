# Current Metrics And Rollups

The app maintains both live system metrics and application-level traffic rollups.

## Live System Metrics

`Netmon::Metrics.read` returns:

- load averages
- memory information from `/proc/meminfo`
- interface RX/TX counters from `/sys/class/net/*/statistics`
- analytics payload derived from `MetricsReporter`
- collector freshness from recent heartbeat events

Endpoints:

- `GET /metrics.json`
- `GET /metrics/series.json`
- `GET /system/series.json`

## Global Analytics

`Netmon::MetricsReporter` currently computes:

- new destination IPs in the last 10 minutes
- unique destination ports in the last 10 minutes
- uplink bytes in the last 10 minutes
- baseline p95 comparisons
- new ASNs in the last hour
- top/rare ports and associated hosts
- anomaly summary indicators

## Per-minute Rollups

### Device rollups

`device_minutes` stores per-device per-minute aggregates such as:

- bytes
- packets
- connection count
- unique destination IPs
- unique destination ports
- unique ASNs
- rare ports
- new destination IP count

### Remote host rollups

`remote_host_minutes` stores per-remote-host per-minute:

- bytes
- packets
- connection count

## Baselines

`device_baselines` store rolling thresholds used in anomaly scoring, such as:

- p95 uplink bytes per minute
- p95 new destination IPs
- p95 unique ports

Recompute task:

- `rake netmon:recompute_baselines`

## Dashboard Usage

The dashboard combines:

- live connections JSON
- top panels JSON
- metric summary JSON
- chart series JSON
- system series JSON

This makes the dashboard responsive, but also means frequent polling can become part of the performance profile if the underlying queries are expensive.

## Operational Note

In simple deployments where UI and ingest share one Puma process, metric and panel polling should be treated as part of the load budget, not as “free background work”.
