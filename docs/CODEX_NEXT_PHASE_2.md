# CODEX_NEXT_ALERTING.md — Non-spam alert policy + incident grouping + /incidents

## Goal
Reduce alert noise and make anomalies reviewable:
- implement an “alert policy” that only surfaces meaningful hits
- suppress NO_RDNS-only alerts
- group bursty repeated hits into incidents (10-minute window)
- optional /incidents page to review incidents and drill down

Constraints:
- Must be deterministic + testable
- Keep storage bounded (cleanup)
- Must not break existing /anomalies and ack flow

---

## Step 1 — Add alert policy config
Add to config (netmon.yml or equivalent):
- alert:
    threshold_score: 70
    required_codes: ["RARE_PORT","UNEXPECTED_PROTO","HIGH_EGRESS","HIGH_FANOUT"]
    suppress_if_only_codes: ["NO_RDNS"]
    incident_window_seconds: 600
    incident_dedup_seconds: 600

Behavior:
- Only “alert” if score >= threshold_score AND intersection(reasons, required_codes) is non-empty
- If reasons == ["NO_RDNS"] (or only contains NO_RDNS and other suppressed-only codes), do not alert

Important:
- Still store AnomalyHits for transparency if you want, but mark them non-alerting.
- Or skip creation for suppressed-only; prefer marking non-alerting so you can audit.

---

## Step 2 — Add Incident model
Create `incidents` table:
- id
- fingerprint (string, NOT NULL, indexed)
- device_id (FK, nullable)
- dst_ip (string, nullable)
- dst_port (int, nullable)
- proto (string, nullable)
- codes_csv (string, NOT NULL)        # sorted unique codes
- first_seen_at (datetime, NOT NULL)
- last_seen_at (datetime, NOT NULL)
- count (int, default 1, null false)
- max_score (int, default 0, null false)
- acknowledged_at (datetime, nullable)
- ack_notes (string, nullable)

Indexes:
- fingerprint
- last_seen_at
- acknowledged_at

Also add `incident_id` to anomaly_hits (nullable FK) so hits link to incidents.

---

## Step 3 — Define incident fingerprint
Fingerprint should group “same underlying issue”:
- base fields:
  - device_id (or src_ip)
  - dst_ip
  - dst_port
  - proto
  - sorted required codes subset (or all codes except NO_RDNS)
Example:
  "#{device_id}|#{dst_ip}|#{dst_port}|#{proto}|#{codes_sorted.join(',')}"

Implementation detail:
- Remove NO_RDNS from fingerprint so it doesn’t split incidents.
- Consider grouping per dst_ip only for HIGH_FANOUT (device-level), where dst_ip may be nil.

---

## Step 4 — Incident upsert algorithm (during ingest)
When a scored connection produces a hit:
1) Evaluate alert policy:
   - alertable? yes/no
2) Create or update anomaly_hit:
   - anomaly_hits.alertable boolean (new column)
   - store reasons_json, score, etc

3) If alertable:
   - compute incident fingerprint
   - find incident with same fingerprint where last_seen_at >= now - incident_window_seconds
     - if found: update
       - last_seen_at = now
       - count += 1
       - max_score = max(max_score, hit.score)
       - codes_csv = union(existing codes, hit codes) (keep sorted)
     - else: create new incident

4) Set anomaly_hit.incident_id = incident.id

Add tests:
- suppressed NO_RDNS-only does not create incident
- hits within 10m window update same incident
- hits after 10m create new incident
- NO_RDNS does not split fingerprint

---

## Step 5 — UI changes
### Dashboard
- Replace “Recent hits” with “Recent incidents” (last 1h, unacknowledged)
  - show: time, device, dst, max_score, codes, count
  - link to /incidents/:id

### /incidents page
- list incidents sorted by last_seen desc
- filters:
  - unacknowledged only
  - min max_score
  - code contains
  - device
  - window quick links (1h/24h/7d)

Row expands:
- show associated anomaly hits (last N) and links to host page

### Incident ack
- Add Ack action:
  - POST /incidents/:id/ack (sets acknowledged_at)
  - optional notes
- When acked, dashboard stops showing it in “Recent incidents”

### Keep /anomalies
- Add column “Incident” with link, and “Alertable” badge

---

## Step 6 — Cleanup policies
Add to cleanup rake task:
- delete incidents older than 90 days (configurable) IF acknowledged OR if last_seen older than retention
- anomaly_hits retention unchanged

---

## Step 7 — Tests
- policy evaluator tests (threshold + required codes + suppress rules)
- incident grouping tests (window + fingerprint normalization)
- request specs: /incidents renders, filters work, ack works

Deliverables:
- alert policy implemented + configurable
- incidents table + grouping logic
- /incidents page + ack flow
- dashboard shows incidents not raw hits
- NO_RDNS-only alerts suppressed
- tests passing
