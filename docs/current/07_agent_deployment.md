# Current Agent Deployment

The Go agent is in `netmon_agent/`.

## Responsibilities

- read conntrack events
- emit `NEW` and `DESTROY` flow events
- tail `dnsmasq` logs and emit normalized `dns_response`
- read NFLOG groups for dropped traffic visibility
- batch and retry events to Rails
- expose Prometheus metrics

## Build

From `netmon_agent/`:

```bash
go build -o netmon_agent ./cmd/netmon_agent
```

Cross-compile example:

```bash
GOOS=linux GOARCH=amd64 go build -o netmon_agent ./cmd/netmon_agent
```

## Config

Primary config file:

- `/etc/netmon-agent/config.yaml`

Key fields:

- `router_id`
- `rails_base_url`
- `auth_token`
- `nflog_groups`
- `dnsmasq_log_path`
- `lan_interfaces`
- `wan_interfaces`
- `lan_subnets`
- `metrics_bind`
- batching / retry / spool settings
- `emit_conntrack_new`

## Systemd

Included unit:

- `netmon_agent/deploy/systemd/netmon-agent.service`

It assumes:

- binary at `/opt/netmon-agent/netmon_agent`
- config at `/etc/netmon-agent/config.yaml`
- spool under `/var/lib/netmon-agent/spool`

## NFLOG Rules

Example rules:

- `netmon_agent/deploy/iptables/netmon-nflog.rules.v4`

These are examples, not universal drop-in rules. Interface names and security posture must match the actual router.

## Verification

- `curl http://127.0.0.1:9109/metrics`
- inspect Rails logs for `/api/v1/netmon/events/batch`
- inspect `netmon_events`, `dns_events`, and `connections`

## Communication With Rails

The agent and Rails communicate over HTTP using:

- `POST /api/v1/netmon/events/batch`
- bearer token auth via `NETMON_API_TOKEN`

The shared secret must match:

- agent `auth_token`
- Rails `NETMON_API_TOKEN`
