# CODEX IMPLEMENTATION: DNS UX Improvements on the Current NetMon Architecture

## Purpose

This document is the implementation-ready version of the DNS UX improvement plan.

It is based on:

- the current shipped NetMon architecture
- the critique in `docs/planning/ux_improvements_critique.md`
- the operational lessons already learned from DNS attribution and performance work

This is not a speculative redesign document.

It is a practical roadmap for improving DNS-oriented operator workflows without forcing a normalized-domain migration.

---

## Architectural Baseline

All implementation work in this phase must start from the system that exists today.

### DNS and attribution source of truth

- The Go router agent is the primary DNS source of truth.
- The agent parses `dnsmasq` logs and emits `dns_response` events.
- Rails ingests those events and persists them to:
  - `dns_events`
  - `dns_event_answers`

### Current domain-bearing data used by the UI

- `connections.last_domain`
- `connections.last_domain_observed_at`
- `remote_host_domains`

### Current retention reality

- raw DNS is pruned from:
  - `dns_events`
  - `dns_event_answers`
- aggregate host-domain history is retained through:
  - `remote_host_domains`

### Current constraints

- attribution quality depends on agent parsing, event order, and Rails backfill behavior
- ingest cost and UI request cost share the same Rails/DB resources
- performance is a design-time requirement
- there is no normalized `domains` table in this phase
- there is no `dns_observations` table in this phase

---

## Phase Goals

This phase is complete when operators can do the following better than they can today:

1. Search by exact domain reliably.
2. Pivot into a domain-oriented view without needing a new domain schema.
3. See clearer domain context on remote-host pages.
4. See useful DNS/domain activity on device pages.
5. Hide noisy internal app/control-plane traffic by default in targeted views without deleting it.
6. Understand what a domain result means based on the underlying data source.

This phase does not require:

- a normalized-domain redesign
- persisted attribution confidence
- a generalized suppression engine
- replacing `remote_host_domains`

---

## Non-Negotiable Rules

1. Do not assume stronger data than the system actually has.
2. Do not hide data invisibly; default-hidden rows must be explainable and revealable.
3. Do not use raw DNS tables in hot paths unless the query is tightly bounded.
4. Do not add large feature work without measuring query and page cost.
5. Preserve current attribution paths unless replacing them deliberately.
6. Keep exact-domain support mandatory; keep registrable-domain support optional.

---

## Data Provenance Rules

Every new DNS/domain-facing UI must keep these distinctions explicit.

### Recent attributed connections

Source:

- `connections.last_domain`

Meaning:

- flows that were actually attributed to a domain

Limits:

- depends on correlation success
- may miss traffic if DNS was unavailable or attribution failed

### Aggregate host-domain association history

Source:

- `remote_host_domains`

Meaning:

- a remote host has been associated with a domain at some point

Limits:

- aggregate history, not full raw DNS detail
- may outlive raw DNS records

### Recent raw DNS detail

Source:

- `dns_events`
- `dns_event_answers`

Meaning:

- recent DNS evidence retained within the pruning window

Limits:

- not durable long-term
- should not drive hot pages without bounded windows

Any new page or section that mixes these sources must label them by provenance.

---

## Search Semantics

This implementation must stop hand-waving “domain search.”

### Required in this phase

- exact-domain search

Definition:

- normalized exact string comparison against the stored domain field
- normalization for this phase means:
  - lowercase
  - strip surrounding whitespace
  - optionally strip a trailing dot if present in user input

### Optional in this phase

- contains/substring search, if kept as a secondary operator convenience

If substring search remains, it must be clearly distinguishable from exact-domain search in UI copy or control behavior.

### Deferred from this phase

- registrable-domain grouping
- fuzzy domain matching
- wildcard domain query language

---

## Performance Guardrails

Every implementation slice must include a performance check.

### What to record for each new query/view/filter

- request path
- query shape
- SQL count
- whether indexes are used
- response time
- row counts returned
- whether the page introduces N+1 behavior

### Hot-path rules

- do not scan raw DNS tables across full history in user-facing pages
- prefer:
  - `remote_host_domains`
  - bounded recent-window connection queries
- add indexes only when justified by the actual query shape

### Success thresholds

These are default working targets for production-like datasets:

- simple search entry pages: comfortably sub-second to low-single-digit seconds
- search result pages: low-single-digit seconds under current data volume
- host detail page: low-single-digit seconds
- any new domain-centric page: no worse than comparable host/search views

If a feature misses these targets, the step is not done.

---

## Implementation Steps

## Step 0: Re-Baseline Current Behavior

### Goal

Build from verified current behavior, not memory.

### Tasks

- document the current DNS pipeline:
  - Go agent DNS parsing
  - Rails DNS ingest
  - backfill behavior
  - pruning behavior
- inventory current pages and query objects that already use:
  - `connections.last_domain`
  - `remote_host_domains`
  - `dns_events`
- document current hiding/filtering behavior already present in connections/dashboard views

### Deliverable

A short in-repo note or checklist summarizing current DNS/domain surfaces and constraints.

### Acceptance

- no later step depends on tables, fields, or semantics that do not exist

---

## Step 1: Define Operator Questions By Page

### Goal

Tie implementation to real operator workflows.

### Tasks

For each page, identify what is still hard to answer:

- `/search/connections`
- `/search/hosts`
- `/remote_hosts/:ip`
- device detail page
- `/anomalies`
- dashboard

Capture concrete questions like:

- “show me flows for exactly `chatgpt.com`”
- “show me what domains this device used recently”
- “show me what domains have pointed at this remote host”
- “show me internal app traffic only when I ask for it”

### Deliverable

A short checklist of unresolved operator questions.

### Acceptance

- each follow-on implementation step clearly answers one or more operator questions

---

## Step 2: Tighten Exact-Domain Search

### Goal

Make exact-domain search explicit and reliable on the current schema.

### Tasks

- add or refine exact-domain search in connection-facing views using:
  - `connections.last_domain`
- add or refine exact-domain search in host-facing views using:
  - `remote_host_domains.domain`
- preserve substring search only if still useful, but separate it conceptually from exact matching
- make the UI wording clear enough that operators know what kind of match they are running

### Data Rules

- exact-domain results must use normalized exact string matching
- do not silently pretend substring search is exact search

### Performance

- verify index usage for exact-match queries
- avoid turning hot search views into broad scans

### Acceptance

- operator can search an exact domain reliably in current connections and hosts surfaces
- matching behavior is clear in the UI and code

---

## Step 3: Add a Lightweight Domain-Oriented Entry Point

### Goal

Provide a domain-first workflow without adding a normalized-domain schema.

### Route Shape

Flexible. Acceptable options include:

- `/domains/search`
- `/domains/:domain`
- a domain panel under `/search`

The route is less important than the workflow.

### Required Sections

The view must separate results by provenance:

1. Recent attributed connections
   - from `connections.last_domain`
2. Remote-host association history
   - from `remote_host_domains`
3. Recent raw DNS detail
   - only if bounded to a safe recent window and clearly labeled

### Required Behavior

- normalize the input domain for exact lookup
- show first/last seen only when that value is truly derivable from the chosen source
- clearly state when raw DNS detail may be incomplete because of pruning

### Explicit Constraints

- do not require a `domains` table
- do not present mixed sources as one unified truth model
- do not do unbounded raw DNS joins in this page

### Acceptance

- operator has a practical domain-first pivot
- the page is honest about what each section means
- performance remains within the same class as existing host/search pages

---

## Step 4: Improve Remote-Host Pages

### Goal

Make host pages tell a clearer domain story.

### Primary Data Source

- `remote_host_domains`

### Secondary Data Source

- recent `connections.last_domain` queries, only when bounded and useful

### Tasks

- improve associated-domain presentation
- sort by recency and/or frequency
- show first seen / last seen / seen count when available
- add links into the domain-oriented entry point
- optionally show recent related devices only if derivable cheaply and correctly

### Explicit Rule

- do not reconstruct full host-domain history from raw DNS on every request

### Acceptance

- host pages explain domain associations more clearly than they do now
- the page remains fast at realistic row counts

---

## Step 5: Improve Device Pages Carefully

### Goal

Make device pages useful for DNS behavior without overstating device identity quality.

### Data Grounding

Treat this work as IP-grounded unless there is strong current evidence that the device model is more reliable.

Use:

- `dns_events.client_ip`
- `connections.src_ip`
- `connections.last_domain`

### Tasks

- add recent domains for the device/IP
- add top domains in a bounded recent window
- show DNS servers used by the device/IP
- show recent attributed flows
- optionally show recent unattributed flows

### Important Semantics

If the page is really showing “activity seen from this IP/device mapping,” the copy should reflect that.

### Explicit Constraints

- do not imply a richer identity model than current data supports
- keep “top domains” windowed and bounded

### Acceptance

- operator can reasonably answer “what domains has this device gone to recently?”
- the feature is accurate about what evidence it is based on

---

## Step 6: Add UI-Level Default Hiding For Internal App Traffic

### Goal

Reduce clutter from expected local app/control-plane traffic while preserving records.

### Initial Scope

- local-to-local traffic
- destination port range `3000..3010`

### Semantics

This is:

- UI/query-default hiding

This is not:

- anomaly suppression
- alert suppression
- record deletion

### Required UX Behavior

- rows are hidden by default only in targeted views
- operators can explicitly reveal them
- the view should indicate that a default hiding rule is active

### Interaction Rules

This step must define how it interacts with existing filters such as:

- hide-state filters
- `only_new`
- other search constraints

### Acceptance

- internal local-local app traffic is hidden by default where it is noisy
- users can reveal it clearly
- behavior is not ambiguous relative to existing filters

---

## Step 7: Document Suppression Semantics Explicitly

### Goal

Prevent future work from overloading the word “suppression.”

### Required Definitions

- UI default hiding
- anomaly suppression
- alert suppression
- internal/control-plane tagging

### Deliverable

A short doc that states:

- what currently exists
- what this phase implements
- what is deferred

### Acceptance

- the codebase and docs use these terms consistently

---

## Step 8: Add Small DNS-Centric Summaries Where They Have Clear ROI

### Goal

Improve visibility without redesigning the app.

### Candidate Additions

Choose only the highest-value additions:

- dashboard summary for recent/new domains
- host search hints for domain association
- device-page summary blocks
- anomaly-page pivots into domain-oriented investigation

### Selection Rule

Only add summaries that answer a clear operator question and can be implemented cheaply on current data.

### Acceptance

- DNS becomes more visible in the product without creating new hot-path regressions

---

## Step 9: Decide Whether Registrable-Domain Support Belongs In This Phase

### Goal

Avoid accidental scope expansion.

### Default Recommendation

Do not implement registrable-domain grouping in this phase unless there is a concrete operator need that exact-domain support cannot satisfy.

### If It Is Pulled Into This Phase

You must first define:

- normalization policy for:
  - ordinary FQDNs
  - single-label names
  - PTR names
  - internal names
  - malformed names
- matching and grouping behavior
- test coverage for the chosen policy

### Acceptance

- either registrable-domain work is explicitly deferred
- or it is implemented with a precise policy, not hand-waving

---

## Step 10: Measure Performance On Every Slice

### Goal

Make performance part of definition-of-done.

### For Each Step Above

Record:

- symptom or target
- suspected layer
- measurement taken
- result
- conclusion
- next action

### Required Tools

Use the smallest tool that answers the question:

- request specs / benchmarks for page behavior
- Rails logs for request timing and SQL count
- query inspection for relation shape
- `EXPLAIN` where query shape is uncertain
- browser network tools only for client-side/resource timing questions

### Acceptance

- each feature slice ships with a performance sanity check
- no major new view/query path is left unmeasured

---

## Step 11: Update Current-State Documentation

### Goal

Keep docs aligned with the implementation that actually ships.

### Required Topics

- agent as DNS source of truth
- Rails DNS ingest and backfill behavior
- current attribution model
- current domain search semantics
- retention/pruning effects on domain-facing pages
- UI default hiding versus suppression semantics

### Acceptance

- future contributors can understand current DNS UX without reading planning docs first

---

## Step 12: Reassess Whether Heavier Architecture Work Is Justified

### Goal

Delay schema-heavy redesign until current architecture proves insufficient.

### Escalation Triggers

Consider future architecture work only if one or more of these becomes true:

- exact-domain search remains too limited or ambiguous
- domain-oriented pages require repeated expensive aggregation
- raw DNS pruning removes detail needed for core operator workflows
- operators need stable first-class domain entities rather than current string pivots
- current host/device/domain UX remains materially inadequate even after this phase

### Acceptance

- any future redesign is justified by observed product pain and measured limits

---

## Minimum Useful Slice

If this work must be split, the first coherent vertical slice should be:

1. exact-domain search tightening
2. lightweight domain-oriented entry point
3. remote-host page domain improvements
4. careful device-page recent-domain visibility
5. UI-level hiding for local-local `3000..3010`
6. documentation of suppression semantics and DNS data provenance

That slice is useful on its own and does not require a schema redesign.

---

## Bottom Line

This implementation plan is intentionally conservative.

It assumes the current architecture is good enough for another meaningful phase of product improvement, provided the work stays honest about:

- data provenance
- identity quality
- retention limits
- performance costs

If those constraints are respected, the app can become substantially more DNS-aware without another large migration.
