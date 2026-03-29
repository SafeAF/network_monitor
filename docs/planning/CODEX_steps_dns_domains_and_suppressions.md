# CODEX STEPS: DNS-Centric Attribution, Domain Pages, and Rule-Based Suppressions

## Operating Rules for This Work

1. Make incremental, reviewable changes.
2. Do not remove raw data currently being ingested.
3. Preserve backward compatibility while migrating away from string-only domain fields.
4. Prefer batched backfills and idempotent jobs/services.
5. Add tests with each schema and service layer change.
6. Preserve performance discipline: no N+1s, no giant table scans in hot pages.

---

## Step 0: Inspect Current App Surface and Domain/DNS Code Paths

### Goals
- understand how `dns_events`, `dns_event_answers`, `connections.last_domain`, and `remote_host_domains` are currently populated
- identify all controllers/views that render domain strings today
- identify current suppression logic and where anomaly scoring happens

### Tasks
- locate models and services using:
  - `DnsEvent`
  - `DnsEventAnswer`
  - `Connection.last_domain`
  - `RemoteHostDomain`
  - `SuppressionRule`
  - `AllowlistRule`
- inventory routes/pages:
  - dashboard
  - search connections
  - hosts
  - new remote hosts
  - devices
- write a short findings note in comments or commit notes if helpful

### Acceptance
- clear map of current ingestion, attribution, and presentation path
- known insertion points for new normalized domain layer

---

## Step 1: Add Domain Models and Schema

### Goals
Create normalized domain records and derived DNS observation records without breaking existing code.

### Schema Changes

Add table: `domains`

Suggested columns:
- `fqdn`, `null: false`
- `registrable_domain`
- `first_seen_at`, `null: false`
- `last_seen_at`, `null: false`
- `dns_event_count`, default `0`, null false
- `device_count`, default `0`, null false
- `remote_host_count`, default `0`, null false
- timestamps

Indexes:
- unique on `fqdn`
- index on `registrable_domain`
- index on `last_seen_at`

Add table: `dns_observations`

Suggested columns:
- `router_id`, `null: false`
- `observed_at`, `null: false`
- `device_id`
- `client_ip`, `null: false`
- `domain_id`, `null: false`
- `qname`, `null: false`
- `registrable_domain`
- `qtype`, `null: false`
- `rcode`
- `resolver`
- `answer_ip`
- `answer_type`
- `dns_event_id`
- `source`, default `"dnsmasq"`, null false
- timestamps

Indexes:
- `(client_ip, observed_at)`
- `(device_id, observed_at)`
- `(domain_id, observed_at)`
- `(answer_ip, observed_at)`
- `(registrable_domain, observed_at)`
- `(dns_event_id)`

### Model Work
Add models:
- `Domain`
- `DnsObservation`

Add associations:
- `Domain has_many :dns_observations`
- `DnsObservation belongs_to :domain`
- optional `belongs_to :device`
- optional `belongs_to :dns_event`

### Acceptance
- migrations run cleanly
- models load
- no existing UI broken

---

## Step 2: Domain Normalization Utilities

### Goals
Create one canonical domain normalization path used everywhere.

### Tasks
Add service/module, e.g.:
- `Netmon::DomainNormalizer`

Functions:
- normalize fqdn
  - lowercase
  - strip trailing dot
  - reject blank / malformed safely
- derive registrable domain (eTLD+1)
- return both exact fqdn and registrable domain

If a public suffix library is needed, add it deliberately and test it.

### Tests
- mixed-case domains normalize to lowercase
- trailing dot stripped
- subdomains map to correct registrable domain
- oddball internal names fail safely or pass through intentionally, depending on policy

### Acceptance
- single shared normalization path exists
- exact and registrable domain are both produced consistently

---

## Step 3: Backfill and Populate `domains` + `dns_observations`

### Goals
Convert existing `dns_events` / `dns_event_answers` into normalized rows.

### Tasks
Add backfill service/job:
- batch through `dns_events`
- for each event:
  - normalize `qname`
  - find/create `Domain`
  - resolve `device_id` from `client_ip` if possible
  - create one `dns_observation` per answer row
  - if no answers exist, still consider whether to record an observation with null `answer_ip` depending on desired query visibility
- update `domains.first_seen_at/last_seen_at/dns_event_count`

Important:
- job must be resumable / idempotent
- avoid loading entire tables into memory
- batch with `find_in_batches`

### Tests
- backfill creates correct domain records
- multiple answers create multiple observations
- repeated events do not duplicate if rerun, or rerun strategy is clearly defined

### Acceptance
- historical DNS data becomes queryable through `dns_observations`
- counts roughly reconcile with prior DNS events

---

## Step 4: Add Device-Domain and Domain-Remote-Host Rollups

### Goals
Create fast rollups for device pages, host pages, and domain pages.

### Schema Changes

Add table: `device_domains`

Columns:
- `device_id`, null false
- `domain_id`, null false
- `first_seen_at`, null false
- `last_seen_at`, null false
- `dns_query_count`, default 0, null false
- `resolved_ip_count`, default 0, null false
- `flow_count`, default 0, null false
- `uplink_bytes`, default 0, null false
- `downlink_bytes`, default 0, null false
- `confidence_max`
- timestamps

Indexes:
- unique `(device_id, domain_id)`
- `last_seen_at`

Add table: `domain_remote_hosts`

Columns:
- `domain_id`, null false
- `remote_host_id`, null false
- `first_seen_at`, null false
- `last_seen_at`, null false
- `seen_count`, default 0, null false
- `device_count`, default 0, null false
- `last_device_id`
- `confidence_max`
- timestamps

Indexes:
- unique `(domain_id, remote_host_id)`
- `last_seen_at`

### Tasks
Create rollup services:
- DNS-driven rollup builder from `dns_observations`
- later flow-enriched rollup updater from `connections`

### Acceptance
- can query "domains for device"
- can query "IPs for domain"
- can query "domains for remote host" via normalized records

---

## Step 5: Extend Connections with Normalized Attribution

### Goals
Move from string-only attribution to normalized and confidence-aware attribution.

### Schema Changes
Add columns to `connections`:
- `last_domain_id`
- `last_registrable_domain`
- `domain_confidence`
- `domain_attributed_at`

Add indexes:
- `last_domain_id`
- `domain_confidence`
- `domain_attributed_at`

Keep existing `last_domain` for now to preserve compatibility during transition.

### Tasks
Add attribution service, e.g.:
- `Netmon::DomainAttribution`

Inputs:
- connection src/dst/proto/ports/timestamps
- device by `src_ip`
- recent and historical `dns_observations`
- remote host by `dst_ip`

Heuristics:
- strong / medium / weak / none
- same device + answer_ip + close time = strong
- same device + historical answer_ip = medium
- global host/domain association only = weak

Update:
- `connections.last_domain_id`
- `connections.last_domain`
- `connections.last_registrable_domain`
- `connections.domain_confidence`
- `connections.domain_attributed_at`

### Tests
- same-device recent query -> strong
- older same-device mapping -> medium
- shared-IP only -> weak
- no DNS context -> none

### Acceptance
- connections carry normalized attribution and confidence
- current pages can continue using `last_domain` while new pages use normalized relation

---

## Step 6: Build Rule-Based Suppression Engine

### Goals
Create configurable suppressions that preserve data but hide expected/internal noise by default.

### Design
Either extend `suppression_rules` substantially or add a new generalized table if current schema is too limited.

Minimum support needed:
- enabled
- scope
- action
- priority
- proto
- src_ip / dst_ip
- src subnet / dst subnet
- local/local matching
- dst_port
- dst_port_range
- domain / registrable_domain
- device_id
- notes

If extending current table is awkward, add a new model:
- `presentation_suppression_rules`

### Tasks
Add matcher service:
- `Netmon::SuppressionMatcher`

Inputs:
- connection
- optional device
- optional remote host
- optional domain
- optional registrable domain

Outputs:
- matched? yes/no
- action(s)
- rule ids / codes

Initial required rule:
- local src
- local dst
- destination port range 3000..3010
- action: suppress by default, de-noise rare-port surfaces

Optional immediate rule:
- router -> Rails server ingest flow specifically tagged as internal control plane

### Tests
- local-to-local port 3000..3010 is preserved but marked suppressed
- external traffic is not accidentally suppressed
- multiple rules resolve deterministically by priority

### Acceptance
- suppressions are rule-driven
- hidden-by-default behavior can be toggled off in UI
- raw records remain searchable

---

## Step 7: Add Domain Index and Domain Show Page

### Goals
Create first-class domain UX.

### Routes
- `GET /domains`
- `GET /domains/:id`

### Domain Index
Features:
- search by FQDN
- search by registrable domain
- recent domains
- top domains
- pageinated results

Suggested columns:
- fqdn
- registrable domain
- last seen
- device count
- remote host count
- dns event count

### Domain Show Page
Sections:
1. summary
2. recent answer IPs
3. devices
4. recent attributed flows
5. optional sibling domains / same registrable domain section

### Performance
Use rollups and eager loading.
Do not compute everything from raw observations on every request.

### Acceptance
- operator can search `chatgpt.com`
- operator can see IPs associated with that domain
- operator can see devices that used it
- operator can see recent flows attributed to it

---

## Step 8: Improve Host / Remote IP Page

### Goals
Show normalized domain associations for remote hosts.

### Tasks
Update remote host show page to include:
- associated domains
- first/last seen per domain
- seen count
- confidence summary
- device count

Prefer `domain_remote_hosts` over raw `remote_host_domains`.

Do not remove old data path until new one is stable.

### Acceptance
- remote host page shows meaningful associated domains, not just WHOIS/RDNS

---

## Step 9: Improve Device Page

### Goals
Make devices a useful pivot for DNS behavior.

### Tasks
Add sections:
- recent domains
- top domains by query count
- top domains by bytes
- new domains first seen recently
- DNS servers used
- flows with no attribution

Prefer `device_domains`.

### Acceptance
- operator can answer "which domains has this device talked to?"

---

## Step 10: Update Search Connections

### Goals
Bring domain and suppression awareness into the main search page.

### Add Filters
- exact domain
- registrable domain
- attribution confidence
- has domain attribution / no domain attribution
- hide suppressed (default on)
- show suppressed
- local-only / remote-only

### Tasks
- wire filters into controller/query object
- add eager loading for domain relation
- show confidence badge in results if useful

### Acceptance
- can search by domain
- can filter noisy internal traffic out by default
- can explicitly inspect suppressed traffic when needed

---

## Step 11: Update Dashboard / New Remote Hosts / Hosts Index

### Goals
Expose domain-centric summaries in the rest of the app.

### Tasks
Dashboard:
- add top domains widget
- add new domains widget
- add unattributed flow count
- add suppressed internal count

New Remote Hosts:
- show associated domains count / top domain if practical
- default-hide suppressed internal entries

Hosts index:
- show domain count / top associated domains if cheap enough

### Acceptance
- DNS intelligence is visible across app, not only on the new domain page

---

## Step 12: Backfill / Migrate Away from `remote_host_domains` String Dependence

### Goals
Reduce dependence on raw-string `remote_host_domains`.

### Tasks
- compare `domain_remote_hosts` vs `remote_host_domains`
- migrate UI queries to normalized model
- keep compatibility path temporarily if needed
- decide whether to keep `remote_host_domains` as legacy materialized table, stop writing to it, or replace it completely

### Acceptance
- normalized domain relations are primary
- legacy string-only path no longer blocks future work

---

## Step 13: Add Saved Query Support for Domains

### Goals
Make domain pivots reusable.

### Tasks
- add support for saved queries with `kind = "domains"` if needed
- support saving domain searches and filtered connection searches by domain

### Acceptance
- operators can save domain-centric investigations

---

## Step 14: Testing and Performance Pass

### Goals
Ensure the feature is real, not just functionally correct.

### Tests
Model tests:
- domain normalization
- attribution confidence
- suppression matching
- rollup updates

Request/system tests:
- domain index
- domain show page
- search with domain filters
- hidden-by-default suppressions toggle
- device page domain lists
- remote host page domain lists

Performance checks:
- page load on large connection table
- page load on large dns_observations table
- no severe N+1s
- indexes used for common paths

### Acceptance
- recent views remain fast
- suppression toggles do not force pathological queries
- pages are stable against large datasets

---

## Step 15: Documentation

### Goals
Document the model so future work stays coherent.

### Write docs covering:
- exact FQDN vs registrable domain
- flow attribution confidence
- suppression philosophy: preserve truth, hide noise by default
- how to backfill DNS observations
- how to add new suppression rules safely

Suggested docs:
- `docs/netmon/domain-model.md`
- `docs/netmon/suppressions.md`
- `docs/netmon/dns-attribution.md`

### Acceptance
- future contributors can understand the feature without reverse engineering it

---

## Suggested Implementation Order

1. inspect current code paths
2. add `domains`
3. add `dns_observations`
4. add domain normalization service
5. backfill DNS observations
6. add rollup tables
7. extend connection attribution with confidence
8. implement suppression engine + default internal port-range rule
9. build domain pages
10. update host/device/search/dashboard surfaces
11. migrate away from string-only domain reliance
12. perf + docs pass

---

## Minimum Slice That Must Ship Together

If work needs to be split, the first complete vertical slice should include:

- `domains`
- `dns_observations`
- normalized backfill
- domain show page
- host page domain section
- device page domain section
- local-local `3000..3010` suppression by default
- search filters for domain + hidden suppressed

That slice is coherent and immediately useful.

---

## Explicit Do / Do Not

### Do
- preserve all raw traffic and DNS records
- normalize domain data
- store both exact and registrable domain
- expose confidence honestly
- suppress internal noise by default, not permanently

### Do Not
- permanently discard internal app traffic
- pretend CDN-shared IP attribution is always exact
- make domain pages depend on raw string scattering in unrelated tables
- hide suppressions so deeply that operator cannot recover the raw view