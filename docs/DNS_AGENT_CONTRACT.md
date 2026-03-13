# DNS Agent Contract

## Source
- The Go agent tails DNS responses from `dnsmasq` log output at `/var/log/dnsmasq.log`.
- Each parsed DNS response is emitted as one `dns_response` event.

## Delivery
- DNS events are delivered through the existing batch API:
  - `POST /api/v1/netmon/events/batch`
- Router-side reliability is handled by the existing agent spool/replay queue.
- Rails does not tail a local JSONL file for DNS ingest.

## Batch schema (existing wrapper)
```json
{
  "router_id": "router-01",
  "sent_at": "2026-03-08T14:20:00Z",
  "events": [
    {
      "type": "dns_response",
      "ts": "2026-03-08T14:19:59Z",
      "data": {
        "client_ip": "10.0.0.20",
        "qname": "github.com",
        "qtype": "A",
        "rcode": "NOERROR",
        "answers": [
          {
            "name": "github.com",
            "type": "A",
            "data": "140.82.113.3",
            "ttl": 60
          }
        ],
        "resolver": "8.8.8.8"
      }
    }
  ]
}
```

## Event semantics
- One `dns_response` event represents one DNS response observed by the agent.
- `answers` may contain multiple A/AAAA answers.
- `answers` may be empty for NXDOMAIN or empty-answer responses.
- `client_ip` is the LAN client that made the query.
- `ts` is the observation time in UTC.
- Full `qname` is stored (no hashing/redaction in this project).

## Scope
- IPv4 required.
- IPv6 optional but supported if present.
- `qtype` may be A, AAAA, CNAME, MX, TXT, etc.
- Initial connection correlation uses A/AAAA answers only.

## Failure model
- Batch delivery is at-least-once due to retries/spool replay.
- Rails must be idempotent for DNS inserts (dedupe key / unique index).
- Malformed DNS event payloads must be logged and dropped without affecting flow ingest.
