# Data model (SQLite)

## remote_hosts
Represents a remote destination host (public dst IP).
- id (integer)
- ip (string, unique, NOT NULL)
- first_seen_at (datetime, NOT NULL)
- last_seen_at (datetime, NOT NULL)
- last_reverse_dns (string, nullable)
- notes (string, nullable)

Seen-before logic:
- "seen before" = remote_hosts.first_seen_at < (now - 60s) OR simply existence in table
- In UI: if record exists, show ✓ and how long ago first seen.

## connections
Represents an active outbound conntrack entry.
Uniqueness key = (proto, src_ip, src_port, dst_ip, dst_port).
- id
- proto (string: "tcp"/"udp"/"icmp"/etc)
- src_ip (string)
- src_port (integer, nullable for icmp)
- dst_ip (string)
- dst_port (integer, nullable)
- state (string, nullable)          # e.g. ESTABLISHED, TIME_WAIT, etc if available
- status_flags (string, nullable)   # e.g. [ASSURED] etc if available
- packets (bigint, NOT NULL, default 0)
- bytes (bigint, NOT NULL, default 0)
- first_seen_at (datetime, NOT NULL)
- last_seen_at (datetime, NOT NULL)
- last_update_at (datetime, NOT NULL)

Optional:
- direction bytes breakdown if conntrack exposes original/reply counters separately:
  - orig_packets, orig_bytes, reply_packets, reply_bytes

## connection_samples (optional, if we want rates / mini-history)
- id
- connection_id (FK)
- ts (datetime)
- packets (bigint)
- bytes (bigint)

Keep only last N minutes via cleanup job.
