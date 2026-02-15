# CODEX_NEXT_SEARCH.md — Powerful Search + Saved Queries (Hosts / Connections / Anomalies)

## Goal
Make search genuinely useful for investigations:
- One “Search” hub with fast filters
- Server-side queries (no heavy JS)
- Works across: remote hosts, connections, anomalies/incidents
- Ability to save a query and re-run it later
- Sortable results + pagination
- “Drill in” links to host/device/incident pages

Non-goals:
- DNS fingerprinting
- LLM integration
- Full-text indexing beyond simple LIKE (unless SQLite FTS is already present)


## Assumptions / Current State
- Routes exist:
  - `GET /search` (index)
  - `GET /search/hosts`
  - `GET /search/connections`
  - `GET /search/anomalies`
  - `POST /saved_queries`
- Models exist:
  - `RemoteHost` (ip, tag, rdns_name, whois_name, whois_asn, first_seen_at, last_seen_at, notes)
  - `Connection` (proto, src_ip, dst_ip, dst_port, bytes/packets, last_seen_at, anomaly_score, anomaly_reasons_json, ...)
  - `AnomalyHit` (occurred_at, device_id, dst_ip, dst_port, score, reasons_json, ack, incident_id, ...)
  - `Device` (ip, name, ...)
  - `SavedQuery` (name, path, params_json, kind)
- UI is Tailwind “hackery” themed (from CODEX_NEXT_UI.md).


---

## Step 1 — Normalize search params + build query objects
### Why
Search endpoints will balloon without structure.

### Deliverables
- Create POROs in `app/queries/`:
  - `Search::HostsQuery`
  - `Search::ConnectionsQuery`
  - `Search::AnomaliesQuery`

Each query object:
- Accepts `params` + returns ActiveRecord relation
- Applies:
  - filter
  - sort
  - pagination
- Has `allowed_sorts` list (whitelist)

Add a small param normalizer:
- `app/lib/search/param_normalizer.rb`
- trims whitespace, downcases proto/tag/codes, validates ints, clamps ranges


---

## Step 2 — Hosts search: filters that actually matter
### Deliverables
Update `/search/hosts` to support query params:

#### Filters
- `ip=` partial match (prefix match encouraged)
- `tag=` (exact)
- `rdns=` substring
- `whois=` substring (whois_name)
- `asn=` exact or substring (whois_asn)
- `seen_since=` (eg `24h`, `7d`) => last_seen_at >= now-window
- `first_seen_since=` same style
- `has_rdns=1|0`
- `has_whois=1|0`
- `notes=` substring
- `dst_port=` (hosts that have ever been seen with this dst_port)
  - via `remote_host_ports` if present, else fallback join via connections

#### Sorts
- `last_seen_at`
- `first_seen_at`
- `ip`
- `tag`
- `whois_name`

#### Output columns
- IP (link to host show)
- tag (badge)
- rDNS
- WHOIS org + ASN
- first_seen / last_seen
- “ports seen” summary (top 3 ports + count), with link to host show

#### Performance
- add/confirm indexes:
  - remote_hosts(tag, last_seen_at)
  - remote_hosts(whois_asn)
  - remote_host_ports(remote_host_id, dst_port) unique already exists

#### UI
- Add compact filter form at top (Tailwind).
- Add “Clear” link.
- Add “Save query” button.


---

## Step 3 — Connections search: the “what is talking to what” view
### Deliverables
Update `/search/connections` to support:

#### Filters
- `device=` (device name or src_ip)
- `src_ip=` exact or prefix
- `dst_ip=` exact or prefix
- `dst_port=`
- `proto=`
- `state=`
- `min_score=`
- `reason=` (matches in anomaly_reasons_json)
- `seen_since=` window (last_seen_at >= now-window)
- `min_total_bytes=`
- `min_uplink_bytes=`
- `min_downlink_bytes=`
- `allowlisted=1|0` (if allowlist_rules exists; interpret by dst_port/dst_ip)

#### Sorts
- `last_seen_at`
- `total_bytes`
- `uplink_bytes`
- `downlink_bytes`
- `dst_ip`
- `dst_port`
- `anomaly_score`

#### Output columns
- proto
- device
- src:port
- dst:port (dst ip link to host page)
- up/down/total (human units)
- score + reasons
- age / last_seen
- whois + rdns (if present)

#### UI niceties
- Quick chips:
  - “Score 50+”
  - “Only NEW”
  - “Hide TIME_WAIT”
  - “Port = 22/53/123/443 quick presets” (optional)


---

## Step 4 — Anomalies search: surgical, non-spam investigation
### Deliverables
Update `/search/anomalies` to support:

#### Filters
- `min_score=`
- `code=` (single) and `codes=` (csv)
- `device=`
- `dst_ip=`
- `dst_port=`
- `proto=`
- `window=` (10m/1h/24h/7d/30d)
- `ack=1|0`
- `incident=1|0` (has incident_id)
- `alertable=1|0` (if present)
- `fingerprint=`
- `summary=` substring

#### Sorts
- `occurred_at`
- `score`
- `dst_ip`
- `dst_port`
- `device`

#### Output columns
- time
- device
- dst ip:port (links)
- proto
- score
- codes
- summary
- ack status + notes
- incident link (if any)
- actions:
  - Ack
  - Suppress rule shortcut (pre-fill suppression form)

#### UX
- Default window = 24h
- Provide “Show only unacked” toggle


---

## Step 5 — Saved Queries: make them first-class
### Deliverables
Enhance `SavedQuery` usage:
- On each search page, add:
  - `name` input + “Save Query” button
  - POST to `/saved_queries`
- Persist:
  - `kind` = hosts|connections|anomalies
  - `path` = `/search/hosts` etc
  - `params_json` = filtered params only (no junk)
- Add a sidebar/section:
  - “Saved Searches”
  - list saved queries filtered by kind
  - click runs it (link to path + params)
- Add delete (optional):
  - `DELETE /saved_queries/:id` (if you want it)

Validation:
- name required, uniqueness per kind optional


---

## Step 6 — Pagination + count limits (don’t melt the box)
### Deliverables
- Add pagination for results:
  - `page=` `per=` (default per=50, max 200)
- For SQLite, use `limit/offset`.
- Display:
  - “Showing X–Y of Z”
- If count is expensive, allow “count capped” mode:
  - If relation is huge, show “10,000+” (optional)


---

## Step 7 — Sorting UI everywhere
### Deliverables
- Use a shared sort helper (`sortable_th`) and apply to:
  - search tables
  - hosts index
  - remote hosts index
  - connections table (if server-rendered)
- Visual:
  - arrow up/down
  - active sort highlighted


---

## Step 8 — Add tag-based filtering to /search/hosts (explicit)
### Deliverables
- In `/search/hosts`, add:
  - Tag dropdown + chips for common tags
  - Tag counts (optional)
- If tags are freeform:
  - still allow exact match + “All” option


---

## Step 9 — “Search hub” (/search) becomes useful
### Deliverables
Make `/search` show:
- 3 big buttons:
  - Hosts / Connections / Anomalies
- A small “global quick search” field:
  - If input looks like IP => go to hosts search with ip=
  - If input is `:port` or `port=443` => go to connections search
  - If input is `code:RARE_PORT` => anomalies search
- Show “Recent saved queries” across all kinds (limit 10)


---

## Step 10 — Tests
### Deliverables
Add specs for each query object:
- ensures filters apply correctly
- ensures sorts are whitelisted
- ensures pagination clamps per<=200
- regression tests for tricky params:
  - invalid ints
  - empty strings
  - mixed case codes

Example spec files:
- `spec/queries/search/hosts_query_spec.rb`
- `spec/queries/search/connections_query_spec.rb`
- `spec/queries/search/anomalies_query_spec.rb`


---

## Acceptance Checklist
- /search/hosts supports tag filter + port filter + seen_since
- /search/connections supports min bytes + score + reason filters
- /search/anomalies supports code filters + ack toggles + window
- All results sortable + paginated
- Saved queries work and are visible per kind
- UI matches existing dark hackery Tailwind theme
- Tests cover key query logic


---

## Notes / Future Enhancements
- SQLite FTS for notes/rdns/whois fields (only if needed)
- Saved query “pin to topbar”
- Export CSV for any search result
- “Open in new tab” default for host drilldowns
