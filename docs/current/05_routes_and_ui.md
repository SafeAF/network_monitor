# Current Routes And UI

## Main HTML Pages

- `/`
  - dashboard
  - active connections table
  - metrics cards
  - charts
  - top panels
- `/anomalies`
  - anomaly hit list with filters and acknowledgment
- `/incidents`
  - incident list
- `/incidents/:id`
  - incident detail with recent hits
- `/remote_hosts`
  - remote host list
- `/remote_hosts/:ip`
  - host detail, recent connections, domains, geo, traceroute state
- `/devices`
  - device list and editing
- `/search`
  - search entry page
- `/search/hosts`
  - host search
- `/search/connections`
  - connection search
- `/search/anomalies`
  - anomaly search
- `/agent_events`
  - recent raw agent event visibility
- `/help`
  - operator reference

## JSON Endpoints

- `/connections.json`
- `/metrics.json`
- `/metrics/series.json`
- `/system/series.json`
- `/dashboard/top_panels.json`
- `/drilldowns/new_dst.json`
- `/drilldowns/unique_ports.json`
- `/drilldowns/new_asns.json`
- `/drilldowns/rare_ports.json`
- `/remote_hosts/:ip/traceroute.json`

## Write Endpoints

- `PATCH /anomalies/:id`
- `POST /incidents/:id/ack`
- `PATCH /remote_hosts/:ip`
- `POST /saved_queries`
- `POST /allowlist_rules`
- `POST /suppression_rules`
- `POST /api/v1/netmon/events/batch`

## UI Model

The UI is server-rendered HTML with selective JSON polling.

Important characteristics:

- dense tables
- investigation-first layout
- dashboard polling for cards/graphs/panels/connections
- local search pages for hosts, connections, anomalies
- operator-editable tags, notes, allowlists, suppressions

## Important Behaviors

### Connections page

- supports hide-state filtering
- supports “only new”
- shows domain correlation when available
- mixes active-ish and recently seen traffic depending on filters

### Remote host detail

- recent connections to the IP
- port history
- recent associated domains
- enrichment fields
- cached traceroute job state

### Search

The search UI is split into dedicated result pages rather than a unified query language backend. The quick-search box routes into those pages.
