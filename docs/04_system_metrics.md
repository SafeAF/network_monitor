# System metrics spec

We display:
- load average (1,5,15)
- CPU usage percent (optional; can be added later)
- memory total/used/free
- disk usage for root filesystem
- interface counters for enp2s0 and enp3s0

## Sources
- loadavg: /proc/loadavg
- memory: /proc/meminfo
- disk: `statvfs` or `df -B1 /` (prefer Ruby StatVFS)
- interface stats:
  - /sys/class/net/<iface>/statistics/rx_bytes, tx_bytes, rx_packets, tx_packets

Update cadence:
- 2s is fine, 5s acceptable.

Implementation:
- Rails controller endpoint `/metrics.json`
- OR push via Turbo streams if already doing websockets.
