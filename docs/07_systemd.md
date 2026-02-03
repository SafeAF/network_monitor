# systemd units (recommended)

Goal: run collector with CAP_NET_ADMIN without running entire Rails server as root.

## netmon-collector.service (example)
- Runs: bin/rails runner "Conntrack::Collector.run"
- Set AmbientCapabilities=CAP_NET_ADMIN
- Restrict filesystem where possible

Codex should generate:
- a systemd unit file in `deploy/systemd/netmon-collector.service`
- optional `netmon-web.service` without elevated capabilities
