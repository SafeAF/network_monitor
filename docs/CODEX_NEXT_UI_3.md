# CODEX_NEXT_UI_V2.md — Drilldowns, Time Scales, More Graphs, Sorting, FAQ

## Goal
Take the current NetMon UI (now themed + coherent) and make it significantly more useful for **investigation** and **trend detection**, while staying:
- Rails server-rendered
- lightweight Stimulus only
- no heavy JS framework
- no business logic changes to anomaly scoring

Primary improvements:
1) Drill-down drawers from summary cards (show which IPs/ports + timestamps)
2) Time scales everywhere (10m/1h/24h/7d)
3) More graphs (loadavg, disk r/w, download bytes)
4) Sorting + column toggles
5) Help/FAQ page for codes and how to interpret them
6) Tag filtering on /search/hosts


## Assumptions
- Existing JSON series endpoint returns this shape:

Example response:

    {
      "timestamps": ["2026-02-12T02:54:44Z", "..."],
      "new_dst_ips_last_10m": [0,0,0,...],
      "unique_dports_last_10m": [2,3,2,...],
      "uplink_bytes_last_10m": [23902473,...],
      "baseline_p95_uplink_bytes_last_10m": [21413113,...],
      "new_asns_last_1h": [0,0,0,...]
    }

- Current pages:
  - `/` dashboard
  - `/anomalies`
  - `/incidents`
  - `/remote_hosts`
  - `/remote_hosts/:ip`
  - `/search/*`
  - `/devices`

- UI already uses Tailwind and shared partials:
  - `_topbar.html.erb`
  - `_filter_bar.html.erb`
  - `_badge.html.erb`
  - `_table.html.erb`
  - `_card.html.erb`
  - `_stat.html.erb`


---

## Step 1 — Add consistent table sorting (connections + remote hosts + anomalies)

### Why
You need fast answers like:
- “highest total bytes”
- “newest remote hosts”
- “highest anomaly score”
- “most recent last_seen”

### Deliverables
#### A) Active connections table
- clickable headers for:
  - `Total bytes`
  - `Up bytes`
  - `Down bytes`
  - `Score`
  - `Age`
  - `Dst IP`
  - `Dst Port`
- show arrow for sort direction
- sorting is server-side with query params:
  - `?sort=total_bytes&dir=desc`

#### B) Remote hosts index table
- sortable:
  - first_seen_at
  - last_seen_at
  - whois_name
  - tag
  - total_bytes_24h (if present; if not, skip)

#### C) Anomalies table
- sortable:
  - occurred_at
  - score
  - dst_ip
  - dst_port
  - device

### Implementation notes
- Add helper:
  - `app/helpers/sort_helper.rb`
- Add `sortable_th(label, sort_key)` helper that:
  - preserves existing params
  - toggles dir asc/desc
  - shows arrow


---

## Step 2 — Add “collapse filter/search bar” with localStorage persistence

### Why
The dashboard is dense and you want to hide filters when monitoring.

### Deliverables
- Add a small caret button on the filter bar.
- Collapses the filter bar content while keeping the top nav.
- Persist state in localStorage:
  - `netmon.filterbar.collapsed=true|false`

### Implementation
- Add Stimulus controller:
  - `app/javascript/controllers/collapse_controller.js`
- Apply it to:
  - dashboard filter bar
  - anomalies filter bar
  - search pages


---

## Step 3 — Drilldown drawer for “New DST IPs” and “Unique DPorts”

### Why
The stat cards are currently “numbers only.”
You want: “what exactly caused that spike and when?”

### Deliverables
#### A) Drawer UI
- A right-side drawer (or modal card) that can be opened/closed.
- Must support:
  - close button
  - Esc key
  - click outside to close
- Should be reusable for multiple drilldowns.

#### B) Drilldown sources
Clicking these cards opens the drawer:
- New DST IPs (10m/1h/24h)
- Unique DPorts (10m/1h/24h)
- New ASNs (1h/24h)

#### C) Drawer contents
For each drilldown row:
- timestamp
- device
- proto
- dst_ip (link to remote host page)
- dst_port (if applicable)
- bytes (pretty units)
- “why included” label (eg: NEW_DST, RARE_PORT)

### Backend endpoints
Create:
- `GET /drilldowns/new_dst`
- `GET /drilldowns/unique_ports`
- `GET /drilldowns/new_asns`

Each accepts:
- `window=10m|1h|24h|7d`
- `device_id=` optional

Return JSON:
- `{ window, generated_at, rows: [...] }`

### Data selection logic (keep simple)
- Use `connections.last_seen_at >= now - window`
- For new_dst:
  - `remote_hosts.first_seen_at >= now - window`
  - join to most recent matching connection if possible
- For unique_ports:
  - group connections by dst_port within window
  - include list of dst_ips per port (limit to 50, show “+N more”)
- For new_asns:
  - use remote_hosts.whois_asn first_seen within window


---

## Step 4 — Time scale dropdown for charts + stat cards

### Why
You want to zoom from 10m to 24h without leaving the dashboard.

### Deliverables
- Every chart gets a dropdown:
  - `10m / 1h / 24h / 7d`
- Selecting it reloads that chart via JSON.
- Stat cards that correspond to charts update consistently.

### Backend changes
Extend existing `/metrics/series` to accept:
- `window=10m|1h|24h|7d`

Rules:
- 10m: bucket = 1m, points=10
- 1h: bucket = 1m, points=60
- 24h: bucket = 5m, points=288
- 7d: bucket = 30m, points=336

Return the same JSON shape (timestamps + arrays).


---

## Step 5 — Add system-level time series: loadavg, disk r/w, download bytes

### Why
Conntrack is great, but the system health signals matter:
- load spikes
- disk churn
- download bursts

### Deliverables
Add these charts to dashboard:
1) Load average (1m series)
2) Disk read bytes per minute
3) Disk write bytes per minute
4) Download bytes per minute (system-wide)

### Storage
Create a new table:
- `system_minutes`

Migration:
- `bucket_ts` datetime unique
- `loadavg1` float
- `disk_read_bytes` bigint
- `disk_write_bytes` bigint
- `rx_bytes` bigint
- `tx_bytes` bigint

Indexes:
- unique bucket_ts

### Collector
Extend collector to capture every minute:
- loadavg: `/proc/loadavg`
- disk stats:
  - `/proc/diskstats` OR `/sys/block/*/stat`
- network rx/tx:
  - `/sys/class/net/#{iface}/statistics/rx_bytes`
  - `/sys/class/net/#{iface}/statistics/tx_bytes`

Pick interface:
- use existing “interfaces” detection logic (already displayed on UI)

Expose series:
- `GET /system/series?metric=loadavg1&window=24h`
- OR fold into `/metrics/series` if preferred


---

## Step 6 — Add “click-to-expand” charts (optional, lightweight)

### Why
Charts are small; sometimes you want to inspect a spike.

### Deliverables
- Clicking a chart opens a modal with a larger chart.
- No new libraries.
- Reuse the same chart rendering code.


---

## Step 7 — Add unit formatting (bytes → KiB/MiB/GiB) everywhere

### Why
Raw bytes are hard to scan.

### Deliverables
- Everywhere bytes appear:
  - show human units (MiB/GiB)
  - tooltip/hover shows raw bytes

Implementation:
- helper: `app/helpers/format_helper.rb`
  - `format_bytes(n)`
  - `format_rate(bytes_per_min)`


---

## Step 8 — Column toggles (NOT draggable columns)

### Why
You want the ability to “move fields around.”
Draggable tables are a pain.
Column toggles get you 80% of benefit.

### Deliverables
- Add a “Columns” dropdown above the connections table:
  - checkboxes for each optional column
- Persist selection in localStorage:
  - `netmon.columns.connections=[...]`
- Default set:
  - proto, device, dst, port, total, score, reasons, whois


---

## Step 9 — Improve drilldowns for “Unique DPorts” and “New DST IPs”

### Deliverables
- When drilldown is open, allow:
  - click port → show list of dst_ips + timestamps
  - click dst_ip → open remote host page in new tab
- Add “copy” button:
  - copy port list
  - copy dst_ip list


---

## Step 10 — Add FAQ / Help page

### Why
This becomes a real tool only if the UI explains itself.

### Deliverables
- Route: `GET /help`
- Nav link in topbar: “Help”
- Content includes:
  - what NetMon is showing
  - what “NEW” means
  - what “SEEN” means
  - how anomaly scoring works
  - what each code means:
    - NEW_DST
    - NEW_ASN
    - NO_RDNS
    - RARE_PORT
    - UNEXPECTED_PROTO
    - PORT_SCAN_LIKE
    - HIGH_EGRESS
    - HIGH_FANOUT
  - allowlist vs suppression
  - incidents vs anomaly hits

Implementation:
- `HelpController#index`
- `app/views/help/index.html.erb`
- Keep it static, Tailwind styled.


---

## Step 11 — Tag filtering for /search/hosts

### Why
You already have remote host tagging.
Filtering by tag is extremely useful.

### Deliverables
- Add tag dropdown to `/search/hosts`
- Support query param:
  - `?tag=cloudflare`
- Add “tag chips” UI:
  - unknown / cloud / cdn / microsoft / google / suspicious / trusted

Backend:
- extend `SearchController#hosts` query


---

## Step 12 — Polish: timestamp labels + “last updated” footers

### Deliverables
- Stat cards show:
  - “Updated: 12:54:44Z”
- Drilldowns show:
  - “Generated at: …”
- Charts show:
  - time range label (eg “Last 24h”)


---

## Step 13 — Add “rare ports” drilldown page (or drawer)

### Why
Port 43 surprised you; you want immediate context.

### Deliverables
- Clicking “Rare Ports” opens drawer:
  - port
  - count
  - dst_ips list
  - first_seen_at / last_seen_at
  - device list


---

## Step 14 — Keep it fast

### Requirements
- Avoid N+1 queries on tables.
- Cap drilldown lists:
  - 200 rows max
  - show “limited to 200” warning
- Add DB indexes if needed.


---

## Acceptance checklist
- Dashboard supports:
  - time scale dropdowns
  - more graphs (loadavg, disk r/w, download)
  - drilldowns for new dst / unique ports / new asns / rare ports
- Tables sortable with arrows
- Filter bar collapsible
- Columns toggle works and persists
- Bytes display in MiB/GiB
- Help page exists and explains codes
- /search/hosts supports tag filter


---

## Notes / Non-goals for this doc
- No DNS fingerprinting (future doc)
- No LLM inspection integration (future doc)
- No React rewrite
- No “drag to reorder columns” (too heavy)
