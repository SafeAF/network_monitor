# Conntrack ingestion spec (router)

## Observed conntrack version
- conntrack-tools: v1.4.7
- `conntrack -L -o extended` outputs two tuples (original + reply) and may include per-tuple counters:
  - `packets=<n> bytes=<n>` appears after each tuple when accounting is enabled.

Example:
ipv4 2 tcp 6 431979 ESTABLISHED
  src=10.0.0.24 dst=104.36.113.111 sport=53284 dport=443 packets=11 bytes=1680
  src=104.36.113.111 dst=135.131.124.247 sport=443 dport=53284 packets=12 bytes=5621
  [ASSURED] mark=0 use=1

## Accounting
We require counters. Ensure:
- net.netfilter.nf_conntrack_acct=1

## Outbound definition
Outbound flow = ORIGINAL tuple where:
- orig.src_ip ∈ 10.0.0.0/24
- orig.dst_ip is NOT RFC1918, not loopback (127/8), not link-local (169.254/16)
- proto any (tcp/udp shown; keep generic)

NAT note:
- reply.dst_ip is the router WAN IP (135.131.124.247) in your setup.
- orig tuple is the LAN client and the true remote destination.

## Collection approach
We do snapshot-based collection first (simpler and stable):
- Every 1–2 seconds, run:
  - `conntrack -L -o extended`
- Parse each line into a ConntrackEntry with:
  - family (ipv4/ipv6), proto (tcp/udp/etc), timeout, state (if present)
  - orig: src_ip, dst_ip, sport, dport, packets, bytes
  - reply: src_ip, dst_ip, sport, dport, packets, bytes
  - flags ([ASSURED] etc), mark, use

Why snapshots:
- v1.4.7 output is easy to parse
- counters are present here
- event stream parsing is optional later

## Data shown in UI
For each outbound entry:
- src = orig.src_ip:orig.sport (LAN host)
- dst = orig.dst_ip:orig.dport (remote)
- proto, state, flags
- uplink_packets = orig.packets
- uplink_bytes   = orig.bytes
- downlink_packets = reply.packets
- downlink_bytes   = reply.bytes
- total_bytes = uplink_bytes + downlink_bytes

## Robustness rules
- Some lines may omit state or counters; treat missing counters as 0.
- UDP lines may omit state field; parse defensively.
- Always treat the FIRST tuple as original, SECOND as reply.
- Ignore entries that don't match outbound definition.
