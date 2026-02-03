# Conntrack parser (v1.4.7) requirements

We parse single-line entries like:

ipv4 2 tcp 6 431979 ESTABLISHED src=10.0.0.24 dst=104.36.113.111 sport=53284 dport=443 packets=11 bytes=1680 src=104.36.113.111 dst=135.131.124.247 sport=443 dport=53284 packets=12 bytes=5621 [ASSURED] mark=0 use=1

or UDP without explicit state token:
ipv4 2 udp 17 12 src=10.0.0.24 dst=34.111.60.239 sport=54756 dport=443 packets=23 bytes=3538 src=34.111.60.239 dst=135.131.124.247 sport=443 dport=54756 packets=77 bytes=101240 mark=0 use=1

Tokenizer strategy:
- Split on spaces.
- Header tokens:
  - tok0=family (ipv4/ipv6)
  - tok2=proto (tcp/udp/icmp/...)
  - tok4=timeout (integer)
  - tok5 may be state (e.g. ESTABLISHED/TIME_WAIT/CLOSE) OR it may be key=value (src=...).
- After header, parse the rest as a stream of tokens.
- The FIRST occurrence set of src/dst/sport/dport/(packets/bytes) belongs to ORIGINAL.
- The SECOND occurrence set belongs to REPLY.
- After both tuples, optional: [FLAGS] mark= use=

Extraction:
- For each tuple, require at minimum src= and dst=. Ports may be missing for some protocols.
- counters optional.

Unit tests must include:
- TCP with state and counters
- TCP with state but without counters
- UDP without state, with counters
- Entry without [ASSURED]
