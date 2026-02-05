# Codex Next Steps (do in order, no scope creep)

## Step 1: Add parser + tests
Create:
- app/lib/conntrack/parser.rb
- spec/lib/conntrack/parser_spec.rb
- spec/fixtures/conntrack/*.txt

Requirements:
- Parser must parse conntrack-tools v1.4.7 `conntrack -L -o extended` output.
- Must support lines with and without `state` token.
- Must split ORIGINAL vs REPLY tuples using the 2nd occurrence of `src=`.
- Must parse per-tuple counters `packets=` and `bytes=` when present; default to 0 when absent.
- Must parse [FLAGS] like [ASSURED].
- Must parse trailing `mark=` and `use=` fields.
- Must ignore unknown tokens like zone=.

Tests:
- Add fixture lines based on real output from router.
- 3 test cases minimum: tcp w/ state+counters, tcp w/ state no counters, udp no state+counters.
- Parser returns nil for malformed lines (missing orig/src/dst or reply/src/dst).

## Step 2: Add “connection key” helper
Add Conntrack::Key.from_entry(entry) that returns stable 5-tuple key:
  "#{proto}|#{orig.src}|#{orig.sport}|#{orig.dst}|#{orig.dport}"

## Step 3: Implement a snapshot reader service (no DB yet)
Create Conntrack::Snapshot.read that runs:
  `conntrack -L -o extended`
and returns array of parsed Entry objects.

Must:
- run command safely, handle failures
- allow dependency injection for command output in tests

## Step 4: Wire a rake task to print outbound connections (dev tool)
Add rake task:
  rake conntrack:print_outbound
that:
- reads snapshot
- filters outbound per docs (LOCAL_SUBNETS in config/netmon.yml)
- prints top 20 by total bytes

# Codex next steps (after parser)

## Step 5: Implement outbound filter module + tests
- app/lib/netmon/filter.rb
- spec/lib/netmon/filter_spec.rb
Outbound if orig.src in LOCAL_SUBNETS and orig.dst not private/link-local/loopback.
LOCAL_SUBNETS loaded from config/netmon.yml (default 10.0.0.0/24).

## Step 6: Add ActiveRecord models + migrations
- RemoteHost(ip unique, first_seen_at, last_seen_at)
- Connection(proto, src_ip, src_port, dst_ip, dst_port, state, flags,
  uplink_packets, uplink_bytes, downlink_packets, downlink_bytes,
  first_seen_at, last_seen_at)
Unique index on (proto, src_ip, src_port, dst_ip, dst_port).

## Step 7: Snapshot reconciler + rake task
- app/lib/netmon/reconcile_snapshot.rb
- lib/tasks/netmon.rake task netmon:ingest_once
Reconciler must:
- read snapshot via Conntrack::Snapshot (support CONNTRACK_INPUT_FILE)
- parse + filter outbound
- upsert remote_hosts (by dst_ip)
- upsert connections (by 5-tuple)
- delete connections not seen in this run (or mark inactive)

Add tests using fixture replay.

## Step 8: Minimal dashboard
- DashboardController#index at /
- render active connections sorted by total bytes desc
- show "NEW" if remote_host.first_seen_at >= now-60s else "SEEN"
No websockets yet.

# Next Steps (9–10)

## Step 9: Continuous ingest loop
- Add `Netmon::Daemon.run(interval: 1.0)` that:
  - calls reconciler once per loop
  - sleeps interval
  - logs errors but keeps running
- Add rake task `netmon:ingest_loop` that runs daemon.
- If CONNTRACK_INPUT_FILE is set, loop replay (read file each iteration).

## Step 10: Live dashboard update via polling (no websockets)
- Add `ConnectionsController#index` (JSON) at `/connections.json`
  - returns current connections sorted by total bytes desc
  - includes seen_before boolean based on remote_hosts.first_seen_at threshold
- Update dashboard view to poll `/connections.json` every 1000ms and patch the table.
- Do NOT add ActionCable yet.

Constraints:
- Do not modify unrelated files.
- Only change files required for steps 9–10.
- Add/extend tests for daemon loop and JSON endpoint.

# Next Steps (11–13)

## Step 11: Seen age + NEW window
- Add helper methods for remote host:
  - seen_age (human readable)
  - new? (first_seen_at within 60s)
- Update UI to show age and NEW/SEEN badge.

## Step 12: Filters and sorting
- Add query params:
  - src_ip, dst_ip, dport, proto
  - hide_time_wait=true
  - only_new=true
- Default sort: total_bytes desc
- Add links/buttons in UI to apply filters.

## Step 13: System metrics tiles
- Implement Netmon::Metrics reading:
  - /proc/loadavg
  - /proc/meminfo
  - /sys/class/net/<iface>/statistics/*
- Add /metrics.json endpoint
- Update dashboard to poll metrics every 2s and display tiles.
- Interfaces configured in config/netmon.yml