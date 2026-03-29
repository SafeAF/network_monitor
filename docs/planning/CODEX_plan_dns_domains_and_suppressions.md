# CODEX PLAN: DNS-Centric Attribution, Domain Pages, and Rule-Based Suppressions

## Purpose

NetMon currently has useful flow-centric and IP-centric visibility, but DNS attribution is still partial and not yet a first-class part of the product.

This project upgrades DNS from "best-effort enrichment" to a core model in the system, while preserving raw traffic and introducing configurable, rule-based suppressions so operator-visible views are quieter by default without destroying data.

---

## Product Decisions

These are settled and should be treated as requirements:

- **Domain representation:** support both exact FQDNs and registrable domains (eTLD+1).
- **Internal traffic handling:** preserve all traffic, but suppress internal noise by default in operator-facing views.
- **Domain page keying:** domain pages are keyed by a normalized domain record, not raw strings scattered through connections.
- **Attribution scope:** domain attribution exists at both the flow level and the remote-host level.
- **Attribution certainty:** show attribution confidence.
- **History retention:** store all-time historical edges; show recent windows by default in UI.
- **Suppressions:** rule-based, configurable, auditable, and reversible.

---

## Current State

Relevant existing schema pieces:

- `dns_events`
- `dns_event_answers`
- `connections`
- `remote_hosts`
- `remote_host_domains`
- `devices`
- `suppression_rules`
- `allowlist_rules`

Observations:

1. DNS data already exists, but the domain model is not first-class.
2. `connections.last_domain` is denormalized and too weak for future needs.
3. `remote_host_domains` stores domains as raw strings and is not enough for:
   - exact vs registrable grouping
   - device/domain pivots
   - confidence-aware attribution
   - domain pages
4. suppressions exist but are too narrow for broader operator-facing "noise management".

---

## Architectural Direction

### 1. Promote DNS into first-class relational entities

Introduce normalized domain records and explicit DNS observations / rollups rather than relying on raw strings.

### 2. Preserve raw ingest, build rollups on top

Do not destroy or over-filter raw data at ingest time. Persist observations, then derive:

- domain records
- device-to-domain edges
- domain-to-remote-host edges
- connection attribution

### 3. Separate raw truth from operator presentation

Internal and expected traffic should still exist in the database, but be tagged/suppressed by default in dashboards, searches, anomaly lists, and "rare port" views.

### 4. Confidence-aware attribution

Not every flow-to-domain mapping is equally strong. Attribution should carry a confidence level and be visible/filterable in UI.

---

## Data Model Changes

## A. New `domains` table

Normalized domain records.

Suggested fields:

- `fqdn` (exact normalized domain, lowercase, no trailing dot)
- `registrable_domain` (eTLD+1 where available)
- `first_seen_at`
- `last_seen_at`
- `dns_event_count`
- `device_count`
- `remote_host_count`

Indexes:

- unique on `fqdn`
- index on `registrable_domain`
- index on `last_seen_at`

Purpose:

- canonical record for domain pages
- stable foreign key target for all future domain relations

---

## B. New `dns_observations` table

Derived, normalized, query-level table built from `dns_events` and `dns_event_answers`.

Suggested fields:

- `router_id`
- `observed_at`
- `device_id` (nullable initially if only client_ip available at ingest time)
- `client_ip`
- `domain_id`
- `qname`
- `registrable_domain`
- `qtype`
- `rcode`
- `resolver`
- `answer_ip`
- `answer_type`
- `dns_event_id`
- `source` (`dnsmasq`, future-proof for other sources)

Indexes:

- `(client_ip, observed_at)`
- `(device_id, observed_at)`
- `(domain_id, observed_at)`
- `(answer_ip, observed_at)`
- `(registrable_domain, observed_at)`

Purpose:

- searchable, normalized DNS history
- direct support for domain pages and pivots
- basis for attribution logic

Note:

- This is a derived relational table, not a replacement for `dns_events`.
- `dns_events` remain raw-ish ingest truth.
- `dns_observations` is the optimized analytics layer.

---

## C. New `device_domains` rollup table

All-time edge between local device and domain.

Suggested fields:

- `device_id`
- `domain_id`
- `first_seen_at`
- `last_seen_at`
- `dns_query_count`
- `resolved_ip_count`
- `flow_count`
- `uplink_bytes`
- `downlink_bytes`
- `confidence_max`

Indexes:

- unique on `(device_id, domain_id)`
- index on `last_seen_at`

Purpose:

- device page
- "which domains has this device talked to?"
- top domains / recent domains / suspicious domain activity

---

## D. New `domain_remote_hosts` rollup table

All-time edge between normalized domain and remote host.

Suggested fields:

- `domain_id`
- `remote_host_id`
- `first_seen_at`
- `last_seen_at`
- `seen_count`
- `device_count`
- `last_device_id`
- `confidence_max`

Indexes:

- unique on `(domain_id, remote_host_id)`
- index on `last_seen_at`

Purpose:

- domain page -> IPs
- host page -> associated domains
- multi-tenant CDN ambiguity inspection

This should ultimately supersede the current string-based `remote_host_domains`.

---

## E. Extend `connections` with normalized attribution

Keep `last_domain` for transition if useful, but move toward normalized attribution columns.

Suggested additions:

- `last_domain_id`
- `last_registrable_domain`
- `domain_confidence`
- `domain_attributed_at`
- `suppressed_by_default` (optional denormalized presentation hint)
- `suppression_reason_codes_json` (optional, if useful for UI)

Indexes:

- `last_domain_id`
- `domain_confidence`
- `domain_attributed_at`

Purpose:

- exact flow-level attribution
- confidence-aware searching and display

---

## F. Generalized suppression model

Existing `suppression_rules` should be expanded or superseded to support configurable operator-facing suppressions, not just anomaly suppression.

Suggested rule dimensions:

- scope: `connection`, `anomaly`, `dashboard`, `host`, `device`, `global`
- match on:
  - src_ip
  - dst_ip
  - src subnet
  - dst subnet
  - src local?
  - dst local?
  - proto
  - dst_port
  - dst_port_range
  - domain
  - registrable_domain
  - device_id
  - remote_host_id
  - tag
- action:
  - suppress_by_default
  - never_alert
  - de_score
  - tag_internal
  - tag_expected
- priority
- enabled
- notes

Minimum required first rule:

- local-to-local traffic with destination port range `3000..3010`
- preserve records
- suppress by default in operator-facing lists and anomaly scoring surfaces

---

## Attribution Model

Attribution should exist at both flow and remote-host levels.

### Confidence levels

Suggested enum:

- `strong`
- `medium`
- `weak`
- `none`

### Suggested heuristics

**Strong**
- same device queried domain
- answer included destination IP
- connection followed within configured recency window

**Medium**
- same device historically resolved domain to destination IP
- close-ish in time or repeated pattern

**Weak**
- destination IP has been associated with domain globally or via other devices, but current device/time evidence is weak

**None**
- no convincing DNS evidence

This confidence should drive UI badges and filters.

---

## UI / Product Work

## 1. Domain index and search

New routes:

- `/domains`
- `/domains/:id`

Features:

- search by exact FQDN
- search by registrable domain
- search by substring
- recent domains
- new domains
- top domains by devices / flows / bytes

---

## 2. Domain show page

Sections:

### Summary
- exact FQDN
- registrable domain
- first seen
- last seen
- unique devices
- unique answer IPs
- total flows attributed

### Recent answer IPs
- remote host/IP
- first seen
- last seen
- seen count
- WHOIS / RDNS
- devices count
- confidence summary

### Devices
- device
- first seen
- last seen
- query count
- flows
- bytes

### Recent attributed flows
- device
- remote IP
- port
- bytes
- score
- reasons
- confidence

### Related domains (optional phase 2)
- sibling FQDNs sharing same registrable domain or IPs

---

## 3. Host / remote IP page improvements

Show:

- associated normalized domains
- recent domains
- domain count
- confidence per domain
- first/last seen per domain
- device count per domain

This turns the remote host page into a real DNS/IP attribution page rather than just WHOIS + RDNS.

---

## 4. Device page improvements

Show:

- recent domains
- top domains by count
- top domains by bytes
- new domains first seen recently
- DNS servers used
- flows lacking domain attribution
- direct external DNS / DoH-ish behavior later

This page should become one of the main pivots in the app.

---

## 5. Search Connections improvements

Add filters:

- domain
- registrable domain
- attribution confidence
- has domain attribution / no domain attribution
- hide suppressed internal noise
- show suppressed
- local-only / remote-only

Default behavior:

- suppress rule-matched internal noise by default
- allow operator to unhide it

---

## 6. Hosts / New Remote Hosts improvements

Add:

- top domains
- domain count
- first device seen
- hide suppressed internal traffic by default

---

## 7. Dashboard improvements

Add widgets:

- top domains
- new domains
- unattributed flows
- suppressed internal traffic count
- devices by unique domains
- top registrable domains

---

## Migration / Compatibility Strategy

This should be incremental, not a giant rewrite.

### Phase 1
- add `domains`
- add `dns_observations`
- backfill from `dns_events` + `dns_event_answers`
- keep current UI working

### Phase 2
- add `device_domains`
- add `domain_remote_hosts`
- backfill rollups
- extend connections with normalized attribution

### Phase 3
- build domain pages
- update host/device pages
- add suppression engine and default rules

### Phase 4
- retire or de-emphasize raw-string-based `remote_host_domains`
- optionally migrate `connections.last_domain` usage to normalized foreign-key usage

---

## Default Suppression Rules

Initial required suppressions:

1. **Internal app traffic**
   - local src
   - local dst
   - dst port range `3000..3010`
   - preserve data
   - suppress by default
   - do not count toward rare-port / anomaly surfaces by default

2. **Router -> Rails ingest path**
   - router IP to Rails server IP on app port
   - preserve data
   - suppress by default
   - mark as internal control plane

3. **Core infrastructure noise** (future)
   - DNS to local resolver
   - DHCP
   - NTP
   - mDNS / SSDP
   - printer chatter
   - operator-configurable

---

## Acceptance Criteria

## Data model
- normalized `domains` exist
- `dns_observations` populated from existing DNS events
- device-domain and domain-remote-host rollups exist
- flow-level attribution has confidence

## UI
- domain index exists
- domain show page exists
- host page shows associated domains
- device page shows domains visited
- search supports domain filters and suppression toggles

## Suppressions
- internal local-to-local `3000..3010` traffic is preserved but hidden by default
- suppressed traffic can be explicitly shown
- suppression rules are configurable and auditable

## Attribution
- exact FQDN and registrable domain both stored
- attribution exists at both connection and remote-host levels
- confidence badge/filter exists

## Performance
- recent views load quickly against large datasets
- backfills are batched and resumable
- heavy queries use rollups/indexes, not raw event scans on every page

---

## Non-Goals for This Slice

Do not include these in the first implementation unless necessary:

- full graph visualization
- automatic domain reputation scoring
- full DoH detection engine
- policy management UI for browsers/endpoints
- external threat intel enrichment

These can come later.

---

## Risks / Design Constraints

1. **CDN ambiguity**
   - many domains map to same IP
   - confidence must be surfaced honestly

2. **Historical data size**
   - `dns_observations` can grow quickly
   - indexes and batched backfills matter

3. **Suppressions hiding too much**
   - all suppressions must be reversible in UI
   - preserve raw data

4. **Exact vs registrable grouping**
   - both must be stored explicitly to avoid lossy approximations later

---

## Implementation Philosophy

- preserve truth, suppress noise
- normalize domains, do not scatter strings
- use rollups for UI speed
- expose uncertainty explicitly with confidence
- make internal control-plane noise visible but quiet