# CODEX_BOOTSTRAP_BEHAVIORAL_DETECTION_AND_FLOW_UI.md

## Goal

Extend NetMon from basic conntrack/enrichment display into a behavior-aware network monitor that can:

1. Score flows by **novelty and deviation from host baseline**
2. Surface stronger reasons for suspicion
3. Visually display connection quality/status:
   - handshake
   - reply
   - assured
   - no reply

This document is a bootstrap plan for Codex to implement the next phase.

---

## High-Level Objectives

### Behavioral Detection
Add per-source-host behavioral profiling so flows can be scored not just by static properties like RDNS or ASN, but by **how unusual the behavior is for that internal host**.

### Flow Status UI
Add a clear visual status display derived from conntrack flags so the operator can immediately tell whether a flow:

- established successfully
- saw a reverse reply
- became assured
- never got a reply

This should reduce operator effort and make scan/noise triage much faster.

---

## Important Clarification

NetMon currently stores **conntrack flags**, not raw TCP flags.

Examples already present:

- `SEEN_REPLY`
- `ASSURED`
- `CONFIRMED`
- `SRC_NAT`
- `SRC_NAT_DONE`
- `DST_NAT_DONE`
- `DYING`

These are still highly useful and should be used for flow-state interpretation.

Do **not** confuse these with raw TCP SYN/ACK/FIN/RST flags.

---

## New Detection Philosophy

Current scoring leans on attributes like:

- NO_RDNS
- NEW_DST
- org/ASN
- port

That is useful but incomplete.

The next step is to score flows by **behavioral rarity**:

- Is this destination new for this host?
- Is this ASN new for this host?
- Is this port unusual for this host?
- Is this host contacting many new destinations in a short period?
- Is the flow upload-heavy compared to normal?
- Is the activity happening at an unusual hour?
- Is the host showing beacon-like repetition?

This turns NetMon from a raw connection viewer into a lightweight behavioral detection system.

---

## New Fields to Add

Add these fields to the enriched/normalized flow model.

### Existing or Derivable
- `src_ip`
- `dst_ip`
- `dst_port`
- `proto`
- `state`
- `flags`
- `up_bytes`
- `down_bytes`
- `total_bytes`
- `first_seen_at`
- `last_seen_at`
- `rdns`
- `org`
- `asn`
- `country`

### New Derived Fields
- `duration_s`
- `hour_bucket`
- `upload_ratio`
- `has_seen_reply`
- `has_assured`
- `has_confirmed`
- `has_no_reply`
- `is_new_dst_for_src`
- `is_new_asn_for_src`
- `is_new_port_for_src`
- `distinct_dsts_for_src_5m`
- `distinct_ports_to_same_dst_5m`
- `no_reply_count_for_src_5m`
- `dns_query_name`
- `is_direct_ip_connection`
- `is_unusual_hour`
- `is_upload_heavy`
- `is_possible_beacon`

### Notes
#### `upload_ratio`
Use a safe definition that avoids divide-by-zero:

`upload_ratio = up_bytes / GREATEST(down_bytes, 1)`

#### `has_no_reply`
This is not a literal conntrack flag. It is a derived boolean:

- true if flow exists but `SEEN_REPLY` is absent
- especially interesting when repeated across many destinations or ports

#### `is_direct_ip_connection`
True when no known DNS name is correlated and the flow appears to target an IP directly.

That is not always suspicious, but it is often more interesting than ordinary domain-mediated HTTPS.

---

## New Profile Tables

Create host baseline/profile tables so scoring can consider historical behavior.

### `host_profiles`
Tracks broad information per internal host.

Suggested columns:
- `src_ip`
- `role`
- `first_seen_at`
- `last_seen_at`
- `total_flows`
- `distinct_dst_ips_7d`
- `distinct_asns_7d`
- `distinct_ports_7d`
- `avg_upload_ratio_7d`
- `usual_hour_bitmap`
- `notes`

### `host_dst_profiles`
Tracks per-host familiarity with specific destinations.

Suggested columns:
- `src_ip`
- `dst_ip`
- `first_seen_at`
- `last_seen_at`
- `seen_count`
- `total_up_bytes`
- `total_down_bytes`
- `last_port`
- `last_proto`
- `last_org`
- `last_asn`

### `host_port_profiles`
Tracks which ports a host commonly uses.

Suggested columns:
- `src_ip`
- `dst_port`
- `proto`
- `first_seen_at`
- `last_seen_at`
- `seen_count`

### `host_asn_profiles`
Tracks which organizations/ASNs a host commonly contacts.

Suggested columns:
- `src_ip`
- `asn`
- `org`
- `first_seen_at`
- `last_seen_at`
- `seen_count`

### Optional: `host_tuple_profiles`
Useful later for beacon detection.

Suggested columns:
- `src_ip`
- `dst_ip`
- `dst_port`
- `proto`
- `first_seen_at`
- `last_seen_at`
- `seen_count`
- `last_10_seen_timestamps` or equivalent derived cache

---

## Detection Rules to Implement

Implement these new rules in scoring.

### Rule: NEW_DST_FOR_SRC
Trigger when a source host contacts a destination IP it has not contacted before.

Suggested score:
- `+25`

Reason:
- `NEW_DST_FOR_SRC`

### Rule: NEW_ASN_FOR_SRC
Trigger when a source host contacts an ASN/org not previously seen for that host.

Suggested score:
- `+20`

Reason:
- `NEW_ASN_FOR_SRC`

### Rule: NEW_PORT_FOR_SRC
Trigger when a source host uses a destination port not previously seen for that host.

Suggested score:
- `+15`

Reason:
- `NEW_PORT_FOR_SRC`

### Rule: NO_RDNS
Keep existing rule.

Suggested score:
- `+10`

Reason:
- `NO_RDNS`

### Rule: UNUSUAL_PORT_FOR_ROLE
Trigger when the host role makes the destination port unusual.

Examples:
- printer making outbound 443 to many destinations
- IoT device using high random ports
- server making outbound consumer-web fanout

Suggested score:
- `+15`

Reason:
- `UNUSUAL_PORT_FOR_ROLE`

### Rule: UPLOAD_HEAVY
Trigger when:
- total bytes exceed threshold
- upload ratio is significantly above host baseline

Suggested score:
- `+20`

Reason:
- `UPLOAD_HEAVY`

### Rule: FANOUT_5M
Trigger when a host contacts many distinct new destinations in a short window.

Suggested score:
- `+25`

Reason:
- `FANOUT_5M`

### Rule: MULTI_PORT_TO_SAME_DST
Trigger when a host hits many distinct ports on the same destination in a short window.

Suggested score:
- `+30`

Reason:
- `MULTI_PORT_TO_SAME_DST`

### Rule: NO_REPLY_BURST
Trigger when a host emits many flows with no `SEEN_REPLY` in a short window.

Suggested score:
- `+20`

Reason:
- `NO_REPLY_BURST`

### Rule: UNUSUAL_HOUR
Trigger when host activity occurs outside its historical time pattern.

Suggested score:
- `+10`

Reason:
- `UNUSUAL_HOUR`

### Rule: DIRECT_IP
Trigger when a flow appears to target an IP directly without correlated DNS.

Suggested score:
- `+10`

Reason:
- `DIRECT_IP`

### Rule: POSSIBLE_BEACON
Trigger when `(src_ip, dst_ip, dst_port)` shows low-variance periodic recurrence.

Suggested score:
- `+20`

Reason:
- `POSSIBLE_BEACON`

### Negative Scoring / Suppression
Reduce score when behavior is well-known for that source host.

Examples:
- destination has been seen many times in the last 7 days
- destination ASN is in per-host allowlist
- traffic pattern matches ordinary browser/update behavior

Suggested score reductions:
- `-20` known destination for host
- `-15` known ASN for host
- `-10` common baseline port for host

Clamp final score to a bounded range, e.g. `0..100`.

---

## Flow Status Derivation Rules

Derive user-facing flow connection badges from conntrack flags.

### `handshake`
Display when:
- `SEEN_REPLY` is present

Interpretation:
- the connection saw reverse traffic
- for TCP this usually means the remote side replied
- in many practical cases this corresponds to successful establishment

Badge text:
- `HANDSHAKE`

Color:
- green or cyan

### `reply`
Display when:
- `SEEN_REPLY` is present

Badge text:
- `REPLY`

Color:
- green

Note:
This is closely related to handshake, but the UI can show both if desired:
- handshake = connection-level success indicator
- reply = explicit reverse-path evidence

If that feels redundant, keep only one of them. If both are shown, be deliberate about why.

### `assured`
Display when:
- `ASSURED` is present

Interpretation:
- conntrack considers the flow established enough to protect from early eviction
- strong indicator of a real, completed connection

Badge text:
- `ASSURED`

Color:
- blue or green

### `no reply`
Display when:
- `SEEN_REPLY` is absent

Interpretation:
- outbound SYN with no reply
- dropped inbound attempt
- incomplete/failed connection
- common in scans, failed probes, blocked traffic, dead targets

Badge text:
- `NO_REPLY`

Color:
- amber or red depending on score/context

### `confirmed`
Optional extra badge when:
- `CONFIRMED` is present

Badge text:
- `CONFIRMED`

Color:
- neutral or blue

This is useful for debugging flow state, but it is less operator-friendly than handshake/reply/assured/no_reply.

---

## Recommended UI Display

Add a compact status section to each flow row.

### Preferred Badge Set
- `HANDSHAKE`
- `REPLY`
- `ASSURED`
- `NO_REPLY`

### Suggested rules
#### Case 1: Successful established connection
Flags include:
- `SEEN_REPLY`
- `ASSURED`
- `CONFIRMED`

Show:
- `HANDSHAKE`
- `REPLY`
- `ASSURED`

#### Case 2: Reply seen, not assured
Flags include:
- `SEEN_REPLY`
- no `ASSURED`

Show:
- `HANDSHAKE`
- `REPLY`

#### Case 3: No reverse traffic
Flags include:
- no `SEEN_REPLY`

Show:
- `NO_REPLY`

#### Case 4: Dying/closed connection
Optionally append a muted badge:
- `CLOSED`
- or keep using state column only

### UI suggestion
Render these badges in a dedicated compact status column or directly under flags.

Example:

`HANDSHAKE  REPLY  ASSURED`

or

`NO_REPLY`

This should be visible at a glance without needing to parse raw conntrack flags.

---

## Visual Treatment

### Keep Raw Flags
Do not remove raw flags from the UI. They are still useful for debugging.

### Add Human-Readable State
Above or beside raw flags, show concise interpreted badges.

Example:

- raw flags:
  `SEEN_REPLY|ASSURED|CONFIRMED|SRC_NAT|SRC_NAT_DONE|DST_NAT_DONE|DYING`

- interpreted badges:
  `HANDSHAKE  REPLY  ASSURED`

That gives both operator clarity and low-level truth.

---

## DNS Correlation

Add best-effort DNS-to-flow correlation.

### Goal
Map a later flow to the DNS query name that likely produced it.

Examples:
- `api.github.com -> 140.x.x.x:443`
- `objects.githubusercontent.com -> 185.x.x.x:443`

### Why
This makes rows vastly easier to understand than raw IPs alone.

### Store
- `dns_query_name`
- `dns_query_seen_at`
- `dns_query_src_ip`

### Correlation idea
When a host resolves a name to an IP, temporarily remember that mapping for a bounded TTL window. If the same host connects to that IP shortly after, annotate the flow.

### Extra signal
If no such DNS correlation exists, mark:
- `DIRECT_IP`

---

## Rolling Window Metrics

Implement rolling calculations over short windows, especially 5 minutes.

### Per source host
- `distinct_dsts_for_src_5m`
- `new_dsts_for_src_5m`
- `no_reply_count_for_src_5m`
- `distinct_asns_for_src_5m`

### Per source+destination
- `distinct_ports_to_same_dst_5m`

These will support:
- scan detection
- fanout detection
- burst detection
- beaconing groundwork

---

## Beacon Detection

Implement a simple first-pass beacon detector.

### Target tuple
- `(src_ip, dst_ip, dst_port, proto)`

### Heuristic
If the last several observations occur at approximately regular intervals, and payloads are small, mark possible beaconing.

### Suggested first implementation
- keep last 10 timestamps
- compute interval deltas
- compute variance or max-min spread
- if variance is low and repeated count exceeds threshold, mark:
  - `POSSIBLE_BEACON`

Do not over-score this at first. Better to surface than to over-alert.

---

## Host Roles

Add optional host role support.

Suggested roles:
- `workstation`
- `phone`
- `server`
- `printer`
- `tv`
- `iot`
- `router`
- `vm_host`
- `unknown`

### Why
Novelty and suspiciousness differ by role.

Examples:
- workstation contacting many new HTTPS destinations is normal
- printer doing the same is suspicious
- server making random outbound fanout may deserve attention

Add simple role-based threshold tuning later.

---

## Schema / Data Flow Recommendation

Prefer separation of concerns.

### Suggested tables
- `flows_raw`
- `flows_enriched`
- `host_profiles`
- `host_dst_profiles`
- `host_port_profiles`
- `host_asn_profiles`
- `alerts`

### Why
Do not keep stuffing everything into one giant table. It will become painful to query, update, and reason about.

---

## Implementation Order

### Phase 1: Derived booleans and UI badges
Implement:
- `has_seen_reply`
- `has_assured`
- `has_confirmed`
- `has_no_reply`

Then render:
- `HANDSHAKE`
- `REPLY`
- `ASSURED`
- `NO_REPLY`

This is the fastest operator-value win.

### Phase 2: Per-host novelty
Implement:
- `is_new_dst_for_src`
- `is_new_asn_for_src`
- `is_new_port_for_src`

Integrate into score and reasons.

### Phase 3: Rolling 5-minute behavior metrics
Implement:
- fanout
- no-reply burst
- multi-port-to-same-dst

### Phase 4: Upload anomaly and unusual hour
Implement:
- `upload_ratio`
- `is_unusual_hour`
- host baseline averages

### Phase 5: DNS correlation and direct-IP tagging
Implement:
- `dns_query_name`
- `is_direct_ip_connection`

### Phase 6: Beacon detection
Implement simple interval-based recurrence detection.

---

## Concrete Acceptance Criteria

### Flow status badges
For every displayed flow:
- if `SEEN_REPLY` present, show `HANDSHAKE` and `REPLY`
- if `ASSURED` present, show `ASSURED`
- if `SEEN_REPLY` absent, show `NO_REPLY`

### New derived fields
Enriched flows include:
- `has_seen_reply`
- `has_assured`
- `has_confirmed`
- `has_no_reply`
- `upload_ratio`
- `is_new_dst_for_src`
- `is_new_asn_for_src`
- `is_new_port_for_src`

### New scoring reasons
Score reason array may include:
- `NEW_DST_FOR_SRC`
- `NEW_ASN_FOR_SRC`
- `NEW_PORT_FOR_SRC`
- `UPLOAD_HEAVY`
- `FANOUT_5M`
- `MULTI_PORT_TO_SAME_DST`
- `NO_REPLY_BURST`
- `UNUSUAL_HOUR`
- `DIRECT_IP`
- `POSSIBLE_BEACON`

### UI clarity
Operator should be able to inspect a row and immediately tell:
- did the remote side reply?
- did the flow establish normally?
- is this destination new for this host?
- why is the score elevated?

---

## Example UI State Mapping

### Example A: Normal HTTPS flow
Flags:
`SEEN_REPLY|ASSURED|CONFIRMED|SRC_NAT|SRC_NAT_DONE|DST_NAT_DONE|DYING`

Display:
- badges: `HANDSHAKE` `REPLY` `ASSURED`
- score: low unless novelty/behavior raises it

### Example B: Failed outbound attempt
Flags:
`CONFIRMED|SRC_NAT|SRC_NAT_DONE`

Display:
- badge: `NO_REPLY`
- score: moderate only if repeated or part of burst/fanout

### Example C: New destination with real session
Flags:
`SEEN_REPLY|ASSURED|CONFIRMED`

Derived:
- `is_new_dst_for_src = true`
- `is_new_asn_for_src = true`

Display:
- badges: `HANDSHAKE` `REPLY` `ASSURED` `NEW_DST` `NEW_ASN`
- score: elevated

---

## Codex Notes

### Do
- preserve raw conntrack flags
- add interpreted flow-state badges
- compute novelty relative to each source host
- keep scoring reasons explicit and human-readable
- keep implementation incremental

### Do Not
- overfit on RDNS absence alone
- treat all high ports as suspicious
- collapse raw flags and interpreted state into one field
- over-alert before host baselines exist

---

## Deliverables

1. Migration(s) for new fields/tables
2. Enrichment logic for derived booleans and novelty flags
3. Scoring logic updates
4. UI badge rendering for:
   - handshake
   - reply
   - assured
   - no reply
5. Tests covering:
   - conntrack flag interpretation
   - novelty detection
   - score reason generation
   - UI rendering of badges

---

## Final Intent

After this phase, NetMon should feel less like a raw flow list and more like an operator-oriented behavioral network monitor.

The immediate value is:
- faster triage
- better scan/noise interpretation
- clearer flow understanding

The strategic value is:
- stronger anomaly detection
- meaningful host baselines
- a foundation for later beaconing and exfil detection