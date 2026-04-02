# CODEX STEPS: DNS-Centric UX and Incremental Domain Improvements on the Current NetMon Architecture

## Operating Rules

1. Work from the current shipped architecture, not a speculative normalized redesign.
2. Keep changes incremental and reviewable.
3. Do not remove or bypass current domain attribution paths unless replacing them deliberately.
4. Preserve raw records and current aggregate history.
5. Treat performance as a design-time requirement on every step.
6. Distinguish clearly between:
   - UI default hiding
   - anomaly suppression
   - alert suppression
   - internal/control-plane tagging

This phase primarily focuses on UI/search/UX improvements and narrowly scoped default hiding in views.

---

## Step 0: Re-baseline the Current DNS and Domain Pipeline

### Goals
Document what actually exists before changing product surfaces.

### Tasks
Inspect and document the current code paths for:

- Go agent DNS parsing and emitted event types
- Rails ingest for DNS events
- persistence into:
  - `dns_events`
  - `dns_event_answers`
- connection attribution updates:
  - `connections.last_domain`
  - `connections.last_domain_observed_at`
- remote host domain history:
  - `remote_host_domains`
- pruning/backfill behavior
- current search filters and host/device page usage of domain data

### Deliverable
A short current-state note in comments or docs describing:
- source of DNS truth
- current persistence path
- current attribution path
- current UI surfaces that already use domain data

### Acceptance
- implementation work starts from current reality
- no follow-on step is based on false assumptions about tables or services that do not exist

---

## Step 1: Define the Current UX Gaps Precisely

### Goals
Turn broad ideas into concrete operator problems.

### Tasks
For each current page, identify what a user still cannot answer easily:

#### Connections search
- can user search by domain easily?
- can user isolate unattributed flows?
- can user hide internal app noise?

#### Host page / host search
- can user see associated domains clearly?
- can user tell recency and frequency?
- can user search by domain association effectively?

#### Device page
- can user answer "what domains has this device gone to?"
- can user see recent domains and top domains?
- can user see DNS server usage?

#### Dashboard / remote hosts pages
- what DNS-related summaries would add the most value?

### Deliverable
A concise checklist of unresolved operator questions by page.

### Acceptance
- next implementation steps are solving explicit operator problems, not just adding nice-looking features

---

## Step 2: Improve Domain Search on Current Data Model

### Goals
Make domain lookup easier using the current schema.

### Tasks
Audit and improve current search/filter paths using:
- `connections.last_domain`
- `remote_host_domains.domain`
- existing host search associations where present

Implement or improve:
- exact domain search in connections
- exact domain search in hosts/remote hosts
- clearer domain filter labels and UI affordances
- optional "has domain attribution" / "no domain attribution" filter if not already present

### Performance Requirements
- add or verify indexes needed for exact-match searches
- avoid full scans in hot paths
- validate on production-like data volume

### Acceptance
- operator can reliably search current data by exact domain
- connection and host searches are more obviously DNS-aware

---

## Step 3: Add a Lightweight Domain-Centric Entry Point

### Goals
Provide a domain-first operator pivot without forcing a new normalized domain architecture.

### Options
Choose one of:
- a lightweight `/domains/search` + result page
- a lightweight `/domains/:domain` style page keyed by normalized exact string
- a domain results panel embedded into existing search UI

The exact route structure is flexible. The important thing is the operator workflow.

### Page / View Requirements
For a searched domain, show as much as can be derived cheaply from current data:

- exact domain searched
- recent matching connections via `connections.last_domain`
- recent remote hosts associated through `remote_host_domains`
- recent devices involved, where derivable
- first seen / last seen if available from current sources
- aggregate counts that are cheap to compute

### Constraints
- do not require a new `domains` table in this phase
- clearly label whether results reflect:
  - recent attributed flows
  - aggregate host-domain history
  - raw DNS history if within retention window

### Acceptance
- operator has a practical domain-first pivot in the current product
- implementation does not force a core schema redesign

---

## Step 4: Improve Host Pages with Better Domain Context

### Goals
Make host pages tell a clearer DNS story.

### Tasks
Enhance host/remote-host detail pages to show:

- associated domains
- recent domains
- first seen / last seen per domain
- seen count where present in `remote_host_domains`
- sorting by recency and/or frequency
- links into domain-centric search or detail views if implemented

If cheap and correct enough, also show:
- recent devices associated with those domain-linked flows

### Backing Data
Primarily:
- `remote_host_domains`
- `connections.last_domain`
- existing host associations

### Performance Requirements
- use current aggregate tables where possible
- avoid reconstructing host-domain history from raw DNS for every request

### Acceptance
- host pages make domain associations substantially more useful than today

---

## Step 5: Improve Device Pages with DNS/Domain Visibility

### Goals
Make devices a meaningful pivot for DNS activity using the current data model.

### Tasks
Enhance device pages to show:

- recent domains associated with the device
- top domains by recency and/or count
- DNS servers used by the device
- recent attributed flows for the device
- optional section for unattributed flows

### Data Strategy
Use current fields carefully:
- DNS often keys off `client_ip`
- connections key off `src_ip`
- device identity should remain grounded in current data quality

Do not over-assume stronger device identity than the current pipeline provides.

### Performance Requirements
- precompute only if necessary
- prefer bounded recent-window queries
- validate page speed under realistic data volume

### Acceptance
- operator can answer "what domains has this device gone to?" reasonably well from the device page

---

## Step 6: Add UI-Level Internal Noise Hiding for Local App Traffic

### Goals
Reduce clutter from expected internal app/control-plane traffic in operator-facing views without changing the underlying data model.

### Immediate Target
- local-to-local traffic
- destination port range `3000..3010`

### Semantics for This Step
- preserve all records
- hide these rows by default in targeted list views such as:
  - connections search
  - relevant dashboard widgets
- provide a visible toggle to show them again

### Important
This step is **not** the same as:
- anomaly suppression
- alert suppression
- never-store rules

It is strictly a UI/query-default behavior in this phase.

### Implementation Guidance
Prefer:
- explicit query scopes / filter params / UI toggles

Avoid:
- introducing a broad generalized suppression engine in this phase unless the current code already has a narrow clean extension point

### Acceptance
- internal local-local app traffic is hidden by default where it clutters operator views
- user can reveal it explicitly
- records remain intact

---

## Step 7: Clarify and Document Suppression Semantics

### Goals
Avoid conflating different kinds of "suppression."

### Tasks
Document the current and desired distinctions between:

- **UI default hiding**
  - hidden by default in selected views
- **anomaly suppression**
  - should not contribute to anomaly scoring or incident generation
- **alert suppression**
  - may still score but should not generate alerts
- **control-plane/internal tagging**
  - classification only

For this phase:
- implement only what is actually needed
- do not collapse all of these into a single mechanic unless the code clearly supports that already

### Deliverable
A short doc or in-repo note making these semantics explicit.

### Acceptance
- future work can build on clear terminology instead of overloaded "suppression"

---

## Step 8: Decide and Scope Registrable-Domain Support Carefully

### Goals
Handle exact-vs-registrable domain support intentionally instead of hand-waving it.

### Tasks
Define normalization policy for:
- normal external FQDNs
- subdomains
- reverse names / PTR-style names
- single-label names
- malformed/odd observed names
- internal/local names

Then decide whether in this phase to support:
- exact domains only, or
- exact domains plus registrable grouping in limited UI contexts

### Important
Do not treat eTLD+1 extraction as free or universally correct.

### Acceptance
- domain grouping policy is explicit
- registrable-domain support, if added now, is deliberate and tested

---

## Step 9: Add Recent DNS/Domain Summaries Where They Help Most

### Goals
Add lightweight DNS-centric summaries to existing high-value pages without redesigning the system.

### Candidate additions
Choose the highest-value ones:

- dashboard widget: recent/new domains
- dashboard widget: top domains in recent window
- dashboard widget: unattributed flow count
- host search result hints: domain count or recent domain
- device page summary: recent domains / DNS servers
- remote-host pages: domain recency and count

### Acceptance
- DNS becomes more visible across the product without requiring a new domain schema

---

## Step 10: Validate Performance Along the Way

### Goals
Treat performance as part of each implementation slice.

### For each new query/view/filter:
Measure:
- response time
- row counts touched
- whether indexes are used
- N+1 behavior
- effect under realistic dataset size

### Guardrails
- no expensive raw DNS joins in hot paths unless bounded tightly
- prefer current aggregate tables like `remote_host_domains` where appropriate
- add indexes only where justified by actual query shape

### Acceptance
- each step includes its own performance sanity check
- no "we’ll optimize later" hand-wave for hot pages

---

## Step 11: Update Documentation to Match Reality

### Goals
Make the docs useful to future contributors and accurate to the current system.

### Docs should cover
- Go agent as DNS source of truth
- Rails DNS ingest path
- current domain attribution model
- limitations from DoH / bypassed local DNS
- late DNS arrival and backfill behavior
- raw DNS retention/pruning model
- current meaning of domain-related UI fields

### Suggested docs
- `docs/netmon/current_dns_pipeline.md`
- `docs/netmon/domain_search_and_host_associations.md`
- `docs/netmon/suppression_semantics.md`

### Acceptance
- docs reflect current system, not speculative future state

---

## Step 12: Reassess Whether Future Architecture Work Is Actually Needed

### Goals
After the incremental product improvements land, evaluate whether a larger redesign is justified.

### Questions to answer
- are current string-based domain pivots still painful?
- is host/device/domain UX sufficient on current architecture?
- is a lightweight domain page enough?
- are performance costs acceptable?
- is pruning forcing a richer derived structure?
- do we need stronger attribution semantics than current fields provide?

### Acceptance
- any future schema-heavy redesign is justified by observed product pain, not aesthetics

---

## Suggested Implementation Order

1. re-baseline the current pipeline
2. define current UX gaps
3. improve exact domain search
4. add lightweight domain-centric entry point
5. improve host pages
6. improve device pages
7. add UI-level internal-noise hiding for local app ports
8. clarify suppression semantics
9. add small DNS-centric summaries where high-value
10. performance validation on every slice
11. update docs
12. reassess future architecture options

---

## Minimum Useful Slice

If this work is split, the first complete vertical slice should include:

- better exact-domain search
- lightweight domain-centric entry point
- host page domain improvements
- device page recent-domain improvements
- hide-by-default local-local `3000..3010` traffic in targeted views
- documentation of suppression semantics and current DNS pipeline

That slice is coherent and immediately valuable.