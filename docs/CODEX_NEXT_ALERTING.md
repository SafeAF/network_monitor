# CODEX_NEXT_ALERTING.md — Non-spam Alerting + Incidents (Burst Grouping)

## Goal
Turn “anomalies” into actionable alerts without constant acknowledging:
- Define an alert policy (thresholds + required codes)
- Suppress low-signal alerts (NO_RDNS-only)
- Group bursts into **incidents** (10-minute window) so you get one thing to review/ack
- Provide an /incidents UI that is actually usable
- Keep everything local-first (no external integrations required)

Non-goals:
- Email/SMS/Push integrations (can be added later)
- DNS fingerprinting
- LLM inspection pipeline
- Rewriting anomaly scoring math (we only decide what is alertable)


## Assumptions / Current State
- `anomaly_hits` table exists with:
  - `fingerprint`, `score`, `reasons_json`, `occurred_at`, `acknowledged_at`, `ack_notes`
  - `suppressed_until`
  - `incident_id`
  - `alertable` boolean (present in schema)
- `incidents` table exists with:
  - `fingerprint`, `device_id`, `dst_ip`, `dst_port`, `proto`, `codes_csv`
  - `first_seen_at`, `last_seen_at`
  - `count`, `max_score`
  - `acknowledged_at`, `ack_notes`
- Routes exist:
  - `GET /incidents`
  - `GET /incidents/:id`
  - `POST /incidents/:id/ack`
- Basic “ack” exists for anomalies (patch) and incidents (post).


---

## Step 1 — Formalize an “Alert Policy” config (single source of truth)

### Requirements
Implement an AlertPolicy class that answers:
- `alertable?(anomaly_hit)` => true/false
- `codes(anomaly_hit)` => array of codes (from reasons_json)
- `suppress_reason(anomaly_hit)` => symbol/string if suppressed by policy

### Policy (as specified)
Only alert when:
- score >= 70
AND
- codes include at least one of:
  - RARE_PORT
  - UNEXPECTED_PROTO
  - HIGH_EGRESS
  - HIGH_FANOUT

Additional rules:
- Suppress NO_RDNS-only alerts entirely unless combined with another code.
  - i.e. if codes == ["NO_RDNS"] => never alertable
  - if codes includes NO_RDNS + something else, NO_RDNS is allowed as supporting info

### Deliverables
- `app/lib/alert_policy.rb` (or `app/models/alert_policy.rb` if you prefer)
- Unit specs in `spec/lib/alert_policy_spec.rb`

### Notes
- Keep it pure (no DB calls inside).


---

## Step 2 — Mark anomaly_hits.alertable at ingest/scoring time

### Why
If alertability is computed on-demand you risk:
- inconsistent behavior if policy changes
- expensive per-row evaluations

### Deliverables
Wherever anomaly hits are created (likely in the reconciler/scorer), set:
- `alertable = AlertPolicy.alertable?(hit)`
- If not alertable, keep stored hit anyway (for review), but it won’t page you.

Add spec:
- creating a hit with score 80 and RARE_PORT => alertable true
- score 80 with only NO_RDNS => alertable false
- score 60 with RARE_PORT => alertable false


---

## Step 3 — Burst grouping into incidents (10 minute window)

### Goal
Group hits by fingerprint into a single incident record spanning a rolling 10-minute window.

### Grouping rule
Given a new anomaly hit with fingerprint F at time T:
- Find the most recent incident for fingerprint F (and optionally device_id/dst_ip/dst_port/proto match)
- If an existing incident has `last_seen_at >= T - 10 minutes`:
  - Update that incident:
    - `last_seen_at = T`
    - `count += 1`
    - `max_score = [max_score, hit.score].max`
    - `codes_csv` union with hit codes
- Else:
  - Create a new incident:
    - fingerprint, device_id, dst_ip, dst_port, proto
    - codes_csv from hit codes
    - first_seen_at = T, last_seen_at = T
    - count = 1, max_score = hit.score

Then set `hit.incident_id = incident.id`.

### Deliverables
- `app/services/incidents/ingest_hit.rb`
  - `call!(hit:)` returns incident
- Specs:
  - creates incident on first hit
  - merges subsequent hits within 10m
  - creates new incident after 10m quiet period
  - unions codes_csv across hits
  - max_score updates

### Indexes
Ensure incident lookup is fast:
- index on `incidents(fingerprint, last_seen_at)`
- if you include device/dst/proto in key, include those in index.


---

## Step 4 — Incident acknowledgement semantics

### Requirements
- Acknowledging an incident should:
  - set incident.acknowledged_at + notes
  - optionally bulk-ack all associated anomaly_hits (recommended)
- Acknowledging an anomaly_hit should not necessarily ack the incident, but may be acceptable to keep independent.
  - Preferred behavior:
    - Incident ack is the main workflow.
    - Individual hit ack remains available for notes.

### Deliverables
- Update `IncidentsController#ack` to:
  - ack incident
  - ack all anomaly_hits with that incident_id where acknowledged_at is null
  - persist ack_notes to incident (and optionally to hits if none)

Specs:
- ack incident sets acknowledged_at
- ack cascades to hits


---

## Step 5 — Suppression that isn’t “Ack forever”

### Problem
Ack is for “I reviewed this.” Suppression is “don’t alert me about this for a while.”

### Deliverables
Implement a suppression action at the incident level:
- UI button: “Suppress 1h / 24h / 7d”
- When applied:
  - set `suppressed_until` on all underlying anomaly_hits
  - OR store suppression rule (better long-term)

Since you already have `suppression_rules`, use them.

#### Minimal approach (fast)
- Add `suppressed_until` handling:
  - AlertPolicy returns false if `hit.suppressed_until && hit.suppressed_until > now`
- Add incident-level controller action:
  - `POST /incidents/:id/suppress?for=1h|24h|7d`
  - sets suppressed_until on associated hits

Specs:
- suppressed hits are not alertable even if score/codes qualify


---

## Step 6 — “Alert feed” that isn’t spam

### Deliverables
Create a “Recent Alertable Incidents” section on dashboard:
- show last 1h (or window selectable)
- only incidents where:
  - `max_score >= 70`
  - `codes_csv` includes one of required codes
  - AND at least one hit in incident is alertable + not suppressed
- show:
  - time range (first→last)
  - device
  - dst_ip:port
  - proto
  - max_score
  - codes
  - count
  - ack status
  - quick actions: Ack / Open / Suppress 1h

Add a badge in topbar:
- “Alerts: N” (unacked alertable incidents in last 24h)


---

## Step 7 — Incidents index page: make it fast to work

### Requirements
`GET /incidents` supports filters:
- `window=1h|24h|7d|30d`
- `min_score=`
- `code=` or `codes=csv`
- `device_id=`
- `ack=0|1`
- `dst_ip=`
- `dst_port=`
- sort:
  - last_seen_at desc (default)
  - max_score desc
  - count desc

UI:
- compact table
- each row links to incident show
- include quick Ack button

### Deliverables
- Add filtering + sorting in `IncidentsController#index`
- Specs for filters (basic coverage)


---

## Step 8 — Incident show page: the investigation workspace

### Deliverables
`GET /incidents/:id` shows:
- summary header:
  - device, dst_ip:port, proto
  - first_seen, last_seen, duration
  - count, max_score, codes
  - ack status + notes
- list of underlying anomaly hits (paginated if large):
  - occurred_at, score, reasons, summary, bytes
  - link to remote_host page for dst_ip
- actions:
  - Ack incident (+ notes)
  - Suppress (1h/24h/7d)
  - Create suppression rule shortcut (optional, prefilled)

Optional:
- “Related activity”:
  - recent connections to same dst_ip in last 24h
  - remote host details panel (rdns/whois/tag)


---

## Step 9 — Data hygiene: incidents and codes normalization

### Deliverables
- Normalize codes storage:
  - codes_csv should be sorted unique CSV (stable output)
  - implement helper:
    - `Incident.normalize_codes(codes_array)` => "A,B,C"

- Ensure fingerprint is stable and purposeful:
  - Current: likely includes device+dst_ip+dst_port+proto+codes group
  - Keep it consistent across the app.

Add specs:
- normalize codes stable order
- grouping doesn’t create duplicate incidents for same fingerprint within window


---

## Step 10 — Guardrails and performance

### Requirements
- Incident ingest must be fast and not cause N+1 queries.
- Use transactions around:
  - create hit
  - attach incident
  - update incident counters

### Deliverables
- Add DB indexes if missing:
  - anomaly_hits(fingerprint, occurred_at)
  - anomaly_hits(incident_id)
  - incidents(fingerprint, last_seen_at)

- Add a hard cap on incident hit list rendering:
  - show first 200, plus “view more” pagination


---

## Acceptance Checklist
- AlertPolicy implemented and tested
- anomaly_hits.alertable set at creation time
- Hits grouped into incidents by fingerprint with 10m window
- /incidents page filters, sorts, and shows unacked alertable incidents
- Ack incident cascades to hits
- Suppression works (time-based) and prevents alertability
- Dashboard shows “Recent alertable incidents” without spammy noise
- NO_RDNS-only never produces alertable incidents unless combined with other codes


---

## Follow-ups (separate docs later)
- External notifications (email/webhook/syslog)
- “Quiet hours” / schedule
- Per-device alert policies
- “Escalation” (if repeats across days)
