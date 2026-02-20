# Netmon Agent Event Schema

POST `/api/v1/netmon/events/batch`

```json
{
  "router_id": "router-01",
  "sent_at": "2026-02-20T14:21:33Z",
  "events": [
    { "type": "firewall_drop", "ts": "2026-02-20T14:21:33.123Z", "data": { } },
    { "type": "flow",          "ts": "2026-02-20T14:21:34.000Z", "data": { } },
    { "type": "dns_bucket",    "ts": "2026-02-20T14:22:00.000Z", "data": { } },
    { "type": "host_identity", "ts": "2026-02-20T14:22:00.000Z", "data": { } }
  ]
}
```

## firewall_drop

```json
{
  "hook": "INPUT",
  "rule_tag": "DROP_IN_SYN",
  "nflog_group": 10,
  "if_in": "enp2s0",
  "if_out": null,
  "src_ip": "203.0.113.9",
  "dst_ip": "198.51.100.2",
  "src_port": 51512,
  "dst_port": 22,
  "l4proto": 6,
  "tcp_syn": true
}
```

## flow

```json
{
  "event": "DESTROY",
  "src_ip": "192.168.1.50",
  "dst_ip": "142.250.72.46",
  "src_port": 51422,
  "dst_port": 443,
  "l4proto": 6,
  "dir": "OUT",
  "bytes_orig": 18233,
  "bytes_reply": 923112,
  "packets_orig": 122,
  "packets_reply": 140,
  "first_seen": "2026-02-20T14:21:00Z",
  "last_seen": "2026-02-20T14:21:34Z",
  "dns_context": {
    "recent_qname_hashes": ["b64:..."],
    "last_seen": "2026-02-20T14:21:55Z"
  }
}
```

## dns_bucket

```json
{
  "bucket_start": "2026-02-20T14:21:00.000Z",
  "client_ip": "192.168.1.50",
  "qtype": "A",
  "qname_hash": "b64:...",
  "count": 37,
  "nxdomain": 2
}
```

## host_identity

```json
{
  "ip": "192.168.1.50",
  "last_seen": "2026-02-20T14:21:55.000Z",
  "recent_qname_hashes": ["b64:...", "b64:..."]
}
```
