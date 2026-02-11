# Roadmap for NetMon (obsidian-grade, Codex-driven)

## Vision
Make NetMon a full-featured local network *activity and anomaly observability tool* with:
- real-time dashboards
- powerful search/investigation capabilities
- signal-focused alerts
- contextual enrichment (DNS/ASN/domain)
- lightweight deployment on a router
- hacky, readable UI with dark theme

---

# Phase 1 — UI polish + alerting (current focus)

### 1) Tailwind “hackery” dark theme
- global layout
- consistent spacing
- styled charts
- consistent badge colors
- tidy tables with truncation

**Value:** makes you actually *want to use* the tool.

**Effort:** Medium

**Doc:** `docs/CODEX_NEXT_UI.md`

---

### 2) Non-spam Alerting + Incident Grouping
- configurable threshold policy
- suppress weak codes
- group bursts into incidents
- /incidents page + ack flow
- link anomaly → incident

**Value:** reduces noise; makes alerts actionable.

**Effort:** Medium–High

**Doc:** `docs/CODEX_NEXT_ALERTING.md`

---

### 3) Host/Connection/Anomaly Search + Saved Queries
- unified search pages
- saved filter presets
- pagination and sort controls

**Value:** investigation UX — find what matters fast.

**Effort:** Medium

**Doc:** `docs/CODEX_NEXT_SEARCH.md` (to be created)

---

# Phase 2 — Contextual Enrichment (high signal gain)

### 4) DNS correlation
- capture DNS answers (resolver log or local cache)
- map dst_ip → domain
- store primary domain per remote_host
- show on UI, search/filter by domain

**Value:** turns IPs into *meaningful names* instantly.

**Effort:** Medium

**Doc:** `docs/CODEX_NEXT_DNS.md` (to be created)

---

### 5) Offline ASN enrichment
- use MaxMind GeoLite ASN locally
- reduce reliance on port 43 whois
- store as `whois_asn` + `whois_org`

**Value:** faster, quieter enrichment.

**Effort:** Low–Medium

---

### 6) DNS REF / mutual correlation
- correlate hostname → IP → services
- derive “expected domain groups” per host

**Value:** reduces false positives enormously.

**Effort:** High (optional)

---

# Phase 3 — Behavioral Baselines + Analytics

### 7) Rolling baselines + trend detection
- day/week baselines per device
- show % change
- “deviation” flags in anomaly scoring

**Value:** high signal detection

**Effort:** Medium

---

### 8) Flow time series analytics
- interactive zoom for minutes/hours
- comparison against historic baseline
- UI widget for timeseries overlays

**Value:** trace anomalies in context

**Effort:** Medium–High

---

# Phase 4 — Alerts & Integrations (ops polish)

### 9) External notifications (optional)
- local notifications
- email alert via local MTA
- Webhook integration (self-hosted only)

**Value:** real ops workflow

**Effort:** Low–Med

---

### 10) Alert suppression policies
- cron silence windows
- per-device spectrums
- aggressive/quiet modes

**Value:** refine signal over time

**Effort:** Medium

---

# Phase 5 — Deployment & Hardening (router-ready)

### 11) Systemd services + deployment playbooks
- `netmon-ingest.service`
- `netmon-web.service`
- firewall + bind interfaces
- orchestrate config

**Value:** frictionless deployment

**Effort:** Low–Med

---

### 12) Capability separation (drop root)
- leverage Linux capabilities (CAP_NET_ADMIN)
- drop privilege for UI
- container options (optional)

**Value:** safer run-time

**Effort:** Med

---

### 13) Device identity & endpoint context
- Auto-import DHCP leases
- MAC → vendor → friendly name
- show on device page

**Value:** no more 10.0.0.20 → real name

**Effort:** Medium

---

# Phase 6 — Long-term / Optional Enhancements

### 14) “Block rule generator”
- one-click generate nftables/ip rule
- user copy-pastes (no auto-apply)

**Effort:** Low

**Value:** ops aid

---

### 15) Multi-host correlator (if you have more routers/devices)
- cluster logs into central netmon
- dedupe/aggregate anomalies across edge

**Effort:** High

**Value:** pro labs

---

### 16) Local LLM assistant mode
- local model reads incident bundles
- outputs natural explanations
- accessible in UI

**Effort:** High

**Value:** semantic interpretation layer

---

## Milestones & Signals of Success

| Milestone | Meaningful Result |
|-----------|------------------|
| Dark theme + layout | You *enjoy* the UI |
| Incidents + alerts | Alerts are actionable, not noise |
| Search + saved queries | You *find* suspicious activity easily |
| DNS correlation | IPs become understandable |
| Baselines + trends | Anomalies make sense in context |
| Deployment scripts | You use this on a real router |
| Block rule generator | You actually block things based on NetMon |

---

## Immediate next steps (condensed)

1) **UI theme** (docs/CODEX_NEXT_UI.md)
2) **Alert policy + incidents** (docs/CODEX_NEXT_ALERTING.md)
3) **Search + saved queries**
4) **DNS correlation**
5) **ASN offline**
6) **Behavioral baselines & analytics**
7) **Deployment + systemd + capabilities**
8) **Ops helpers (block rules, notifications)**

---

## Tips for Codex Instruction Docs

- Split by *feature set*, not by step number.
- Name docs semantically (search, dns, alerts, ui).
- Always include:
  - What to build
  - Where it appears
  - Configurable knobs
  - Tests to enforce correctness
  - Do not touch unrelated files
  - Minimal performance guidance

---

## Rough Effort Bands

| Band | Approx |
|------|--------|
| ⭐ | trivial UI tweak or config |
| ⭐⭐ | simple feature or filter |
| ⭐⭐⭐ | new page + logic + tests |
| ⭐⭐⭐⭐ | cross-cutting feature + data model |
| ⭐⭐⭐⭐⭐ | major enrichment / telemetry layer |

---

If you want, I can **generate all the next Codex doc stubs automatically** (just titles + placeholder sections) so you can pick which one to send into Codex next — effectively a TL;DR of all these roadmap docs ready for actionable work.
::contentReference[oaicite:0]{index=0}
