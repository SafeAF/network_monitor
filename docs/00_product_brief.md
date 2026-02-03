# NetMon (router conntrack monitor)

## Goal
A lightweight, local-only web interface to monitor outbound connections from the LAN to the internet in near real time, showing:
- connection tuple (src_ip:src_port -> dst_ip:dst_port, proto)
- connection state/flags (as available from conntrack)
- per-connection packets + bytes (rx/tx or total as provided by conntrack)
- "seen before" marker for remote hosts (dst IP)
- system load (1/5/15), memory usage, disk usage
- interface stats for LAN (enp3s0) and WAN (enp2s0): rx/tx bytes + packets

## Environment
Router interfaces:
- WAN: enp2s0, inet 135.131.124.247/21
- LAN: enp3s0, inet 10.0.0.1/24

We consider outbound connections as those whose ORIGINAL direction has:
- src_ip in 10.0.0.0/24
- dst_ip not in RFC1918 ranges (10/8, 172.16/12, 192.168/16), not loopback

## UX requirements
- One page dashboard at `/` showing:
  - Live table of active outbound connections (auto-updating)
  - Top remote destinations by bytes in the last N minutes
  - Search/filter by src_ip, dst_ip, dst_port, proto
  - Toggle to show only NEW connections
  - "Seen before" indicator for dst_ip (and optional hostname if resolvable)
  - System load widget and interface stats widget
- Update cadence: ideally ~1s; acceptable up to 2–3s.
- Local network only; no auth initially, but restrict bind to LAN or require basic auth in production.

## Non-goals (for now)
- Deep packet inspection
- Per-process attribution
- Historical charts beyond simple rollups (can add later)
