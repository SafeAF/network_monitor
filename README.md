# Network Monitor

Network Monitor is a two-part LAN monitoring system:

- `netmon/`: a Rails web app for investigation, search, metrics, anomaly review, and incidents
- `netmon_agent/`: a Go router agent that collects conntrack, DNS, and NFLOG events and ships them to Rails

The current documentation entrypoint is:

- `docs/current/00_product_brief.md`

The older `docs/00_*` through `docs/09_*` files are preserved as planning-era documents.

## Repo Layout

```text
docs/              planning docs, debugging docs, and current-state docs
netmon/            Rails app
netmon_agent/      Go router agent
```

## Architecture

### Preferred production-ish shape

1. Run the Go agent on the router.
2. Run the Rails app on a LAN-visible host.
3. Configure the agent to send batched events to Rails:
   - `POST /api/v1/netmon/events/batch`
4. Set the same shared token in:
   - agent `auth_token`
   - Rails `NETMON_API_TOKEN`

### Alternate local/dev shape

You can also run the Rails app by itself and ingest conntrack snapshots directly with rake tasks. That mode is simpler but has less capability than the Go agent path.

## Rails App

Path:

- `netmon/`

### Prerequisites

- Ruby/Bundler
- SQLite3
- Node.js
- Yarn or npm

### Install

```bash
cd netmon
bundle install
yarn install
bin/rails db:prepare
```

### Run in local development

```bash
cd netmon
bin/dev
```

This starts:

- Rails on port `3000`
- JS build watch
- CSS build watch

### Run Rails without foreman

```bash
cd netmon
yarn build
yarn build:css
bin/rails server -b 0.0.0.0 -p 3000
```

### Important Rails environment variables

- `NETMON_API_TOKEN`
- `RAILS_ENV`
- `RAILS_MAX_THREADS`
- `WEB_CONCURRENCY`

Useful debug variables:

- `RAILS_LOG_LEVEL`
- `RAILS_VERBOSE_QUERY_LOGS`
- `RAILS_VIEW_ANNOTATIONS`
- `RAILS_SERVER_TIMING`

### Useful Rails tasks

```bash
cd netmon
bin/rails netmon:ingest_once
bin/rails netmon:ingest_loop
bin/rails netmon:recompute_baselines
bin/rails netmon:cleanup
bin/rails netmon:dns_prune
```

## Go Agent

Path:

- `netmon_agent/`

### What it does

- reads conntrack events
- reads `dnsmasq` logs
- reads NFLOG groups
- batches and retries events to Rails
- exposes Prometheus metrics

### Build

```bash
cd netmon_agent
go build -o netmon_agent ./cmd/netmon_agent
```

Cross-compile for Linux amd64:

```bash
cd netmon_agent
GOOS=linux GOARCH=amd64 go build -o netmon_agent ./cmd/netmon_agent
```

### Example config

Create `/etc/netmon-agent/config.yaml`:

```yaml
router_id: "router-01"
rails_base_url: "http://192.168.0.10:3000"
auth_token: "replace-me"

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

qname_hash_salt: "replace-me"
qname_hash_cap: 200
emit_conntrack_new: true

http_timeout: 5s
http_retry_max: 5
http_retry_base: 1s
http_flush_workers: 2
spool_replay_interval: 5s
heartbeat_interval: 30s

conntrack_read_buffer: 4194304
conntrack_workers: 2
conntrack_event_buffer: 4096
```

### Run manually

```bash
cd netmon_agent
./netmon_agent -config /etc/netmon-agent/config.yaml
```

### Systemd

Included unit:

- `netmon_agent/deploy/systemd/netmon-agent.service`

Install example:

```bash
cp netmon_agent/deploy/systemd/netmon-agent.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable netmon-agent
systemctl start netmon-agent
```

### NFLOG rules

Example rules live at:

- `netmon_agent/deploy/iptables/netmon-nflog.rules.v4`

Review and adapt interface names and security behavior before use.

## Getting Rails And The Agent Talking

### Rails side

Set:

```bash
export NETMON_API_TOKEN="replace-me"
```

Run Rails:

```bash
cd netmon
bin/dev
```

### Agent side

Set the same token in `/etc/netmon-agent/config.yaml`:

```yaml
auth_token: "replace-me"
rails_base_url: "http://<rails-host>:3000"
```

### Verify end to end

1. Agent can reach Rails:

```bash
curl http://<rails-host>:3000/up
```

2. Agent metrics endpoint responds:

```bash
curl http://127.0.0.1:9109/metrics
```

3. Rails receives batches:

- check Rails logs for `/api/v1/netmon/events/batch`

4. Rails stores events:

```bash
cd netmon
bin/rails runner 'puts NetmonEvent.order(id: :desc).limit(5).pluck(:event_type, :created_at)'
```

5. DNS data appears:

```bash
cd netmon
bin/rails runner 'puts DnsEvent.count; puts DnsEventAnswer.count'
```

## Deploying The Rails App

The repo contains a Kamal-oriented deploy config in:

- `netmon/config/deploy.yml`

Current production config expects:

- Puma
- SQLite-backed Rails databases under `storage/`
- persistent volume mounts

Before deploying production:

1. set `RAILS_MASTER_KEY`
2. set `NETMON_API_TOKEN`
3. confirm `config/deploy.yml`
4. confirm hostnames, registry, and volumes
5. prepare the database:

```bash
cd netmon
bin/rails db:prepare RAILS_ENV=production
```

## Running Tests

Rails:

```bash
cd netmon
bundle exec rspec
```

Agent:

```bash
cd netmon_agent
go test ./...
```

## Important Notes

- The current product works in simple LAN deployments, but sustained ingest plus SQLite plus a single shared Rails process can become a bottleneck.
- If pages feel slow, inspect ingest pressure first, not just the page controller.
- See:
  - `docs/debugging/rails-slow-page-checklist.md`
  - `docs/debugging/netmon-performance-postmortem-2026-03-29.md`
