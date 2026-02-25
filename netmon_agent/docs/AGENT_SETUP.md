# Netmon Agent Setup

## Build

```bash
cd /opt/netmon-agent
GOOS=linux GOARCH=amd64 go build -o netmon_agent ./cmd/netmon_agent
```

## Config

Create `/etc/netmon-agent/config.yaml`:

```yaml
router_id: "router-01"
rails_base_url: "http://<rails_lan_ip>:3000"
auth_token: "<shared-secret>"

nflog_groups: [10, 11]
dnsmasq_log_path: "/var/log/dnsmasq.log"

lan_interfaces: ["enp3s0"]
wan_interfaces: ["enp2s0"]
lan_subnets: ["10.0.0.0/24"]

metrics_bind: "127.0.0.1:9109"

batch_max_events: 250
batch_max_wait: 1s
queue_depth: 2000

spool_dir: "/var/lib/netmon-agent/spool"
spool_max_bytes: 52428800

qname_hash_salt: "change-me"
qname_hash_cap: 200
emit_conntrack_new: false
http_timeout: 5s
http_retry_max: 5
http_retry_base: 1s
spool_replay_interval: 5s
heartbeat_interval: 30s
```

Set the Rails API token in the server environment:

```
NETMON_API_TOKEN=<shared-secret>
```

## Install systemd

```bash
cp deploy/systemd/netmon-agent.service /etc/systemd/system/netmon-agent.service
systemctl daemon-reload
systemctl enable netmon-agent
systemctl start netmon-agent
```

## NFLOG rules

Apply the rules from `deploy/iptables/netmon-nflog.rules.v4` or insert the chains before your final drop rules.

## Verify

- `curl http://127.0.0.1:9109/metrics`
- Check Rails logs for `/api/v1/netmon/events/batch`
- Confirm `netmon_events` has rows
