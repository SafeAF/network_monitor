# CODEX PLAN: DNS-Centric UX and Incremental Domain Improvements on the Current NetMon Architecture

## Purpose

This plan replaces earlier DNS/domain planning that assumed a larger normalized-domain redesign as the immediate next step.

The current goal is narrower and more practical:

- improve DNS-centric operator workflows
- improve domain search and domain visibility
- improve host and device pages
- improve connection search
- reduce internal/control-plane noise in operator-facing views
- do all of the above on top of the architecture that actually exists today

This is a near-term product plan, not a speculative redesign.

---

## Product Direction

We want the app to become more DNS-aware and more useful for answering questions like:

- what domains has a device gone to?
- what IPs have been associated with a domain?
- what domains are associated with a remote host?
- which domains were newly seen recently?
- which current views are polluted by internal app/control-plane traffic?

We are **not** treating a normalized `domains`/`dns_observations` architecture as the baseline implementation for this phase.

---

## Current System Baseline

These facts must anchor all implementation work in this phase.

### Ingest and source of truth
- The Go router agent is the primary source of DNS truth.
- The agent parses `dnsmasq` logs and emits DNS-related events.
- Rails ingests those events and persists them.

### Existing DNS/domain persistence
- raw-ish DNS is stored in:
  - `dns_events`
  - `dns_event_answers`
- connection-level domain attribution is currently stored in:
  - `connections.last_domain`
  - `connections.last_domain_observed_at`
- remote-host domain history is currently stored in:
  - `remote_host_domains`

### Existing product capabilities
- connections can already show attributed domains via `last_domain`
- host-related views already have some domain associations
- host search can already use associated domain information
- raw DNS is pruned over time, while aggregate host-domain associations are intentionally preserved

### Existing constraints
- attribution correctness depends heavily on:
  - Go agent DNS parsing quality
  - event ordering / late DNS arrival
  - Rails ingest/backfill logic
- performance is a first-order concern
- current suppression/allowlist systems are narrower than a full presentation-layer policy engine

---

## What Already Exists and Works

The current system is not "DNS is just decoration." There is already meaningful value here.

Shipped/working behavior includes:

- agent-side DNS parsing and correlation
- storage of DNS events and answers
- late DNS backfill that can update recent flows
- connection attribution through `last_domain`
- remote-host domain retention through `remote_host_domains`
- domain display in connections and host-related views
- search support using current domain-related fields
- raw DNS pruning with retained aggregate associations

This plan builds on that foundation instead of discarding it.

---

## Near-Term Product Goals

## 1. DNS-centric UX improvements
Operators should be able to move through the app by following DNS evidence, not only IPs and flows.

## 2. Better domain search
Searching by domain should be easier, more obvious, and more useful across current pages.

## 3. Better host pages
A remote host page should better explain which domains have been associated with that host and when.

## 4. Better device pages
A device page should better answer "what domains has this device gone to?"

## 5. Better connection search
Connections search should support more DNS-aware filtering and better default hiding of noisy internal app traffic.

## 6. Preserve truth while reducing noise
We want to preserve all raw data but improve default presentation by hiding internal/control-plane noise in specific views.

---

## Near-Term Scope

This phase should stay inside the current architecture wherever possible.

### In scope
- domain-centric UX backed by existing tables
- lightweight domain search / domain page patterns
- improved host page domain sections
- improved device page DNS/domain sections
- improved connection search filters
- UI/query-level hidden-by-default filtering for internal local-local port ranges like `3000..3010`
- documentation of current DNS pipeline and limitations

### Out of scope for this phase
- mandatory introduction of `domains` table
- mandatory introduction of `dns_observations`
- broad generalized suppression engine across all product surfaces
- persisted attribution confidence enums unless a very narrow use case justifies them
- full migration away from `remote_host_domains`
- full graph/relationship redesign

---

## Known Limitations in the Current Architecture

These are the problems the near-term work should address or at least clarify.

## 1. Domain discovery is still scattered
Domain information exists, but the operator experience is still mostly:
- flow-centric
- host-centric
- string-field-centric

There is no obvious domain-first pivot yet.

## 2. Device pages are underpowered for DNS use
The app can show devices, but not yet in a way that naturally answers:
- which domains has this device used recently?
- what are its top domains?
- what DNS servers is it using?
- what flows have no domain attribution?

## 3. Host pages could tell a clearer story
A host page should better answer:
- what domains have pointed to this host?
- how recently?
- how often?
- from which devices?

## 4. Internal app/control-plane noise is visible in operator views
Local-to-local app traffic, especially on internal app ports, can muddy the UX.

We want to preserve it, but hide it by default in targeted UI surfaces.

## 5. Suppression semantics are not yet clearly separated
We need to distinguish:
- hidden by default in UI
- excluded from anomaly scoring
- excluded from alerting
- tagged as control-plane/internal

This phase primarily targets **UI/query-level hiding**, not a universal policy engine.

## 6. Registrable-domain grouping is desirable but not yet fully specified
Exact domain strings are already useful.
Registrable-domain grouping may be useful, but it should be introduced carefully and only with explicit normalization policy.

---

## Product Increments for This Phase

## A. Lightweight domain-first UX

### Goal
Make domains easier to inspect without forcing a new core data model.

### Product shape
- add a domain search entry point
- optionally add a lightweight domain detail page backed by current tables
- support domain lookup using current string-based data sources

### What a lightweight domain page should show
For a domain string like `chatgpt.com`:

- exact domain searched
- recent associated IPs / remote hosts
- recent devices tied to that domain
- recent connections with `last_domain = domain`
- first seen / last seen where derivable
- host/domain history from `remote_host_domains`

This page should be driven by current data, not by assuming a `domains` table exists.

---

## B. Host page improvements

### Goal
A host page should better explain host-domain associations.

### Desired additions
- associated domains section
- recent domains for this host
- first seen / last seen per domain
- seen count where available
- devices recently involved if derivable cheaply
- better domain sorting and presentation

### Backing data
Primarily:
- `remote_host_domains`
- `connections.last_domain`
- `dns_event_answers` / `dns_events` if needed carefully

---

## C. Device page improvements

### Goal
A device page should better answer "what domains has this device gone to?"

### Desired additions
- recent domains seen from this device
- top domains by recency and/or count
- DNS servers used
- connections with domain attribution
- connections without domain attribution
- optional "new domains recently seen from this device"

### Backing data
Primarily:
- `dns_events.client_ip`
- `connections.src_ip`
- `connections.last_domain`

Important:
- current truth is often keyed by `client_ip`
- do not assume device identity is richer than it is

---

## D. Search improvements

### Goal
Make the existing connections/hosts searches more DNS-aware and less noisy.

### Desired additions
- better domain filter visibility
- exact-domain search
- optional registrable-domain grouping later
- "has domain attribution" / "no domain attribution"
- hidden-by-default local-local internal app traffic for configured port ranges
- toggle to show hidden internal traffic

This should initially be a UI/query behavior, not a new generalized suppression subsystem.

---

## E. Internal-noise handling in operator views

### Goal
Reduce clutter from expected internal app/control-plane traffic while preserving the records.

### Immediate target
- local-to-local traffic
- destination ports `3000..3010`

### Semantics for this phase
- preserve the records
- do not delete them
- do not assume anomaly suppression automatically
- hide them by default in selected operator-facing list views
- allow explicit reveal/toggle

### Important distinction
This is primarily a **presentation and query default** improvement in this phase.

It is not yet a commitment to a full generalized suppression engine.

---

## Registrable Domain Support

We do want both:
- exact FQDN
- registrable domain / eTLD+1

But in this phase registrable-domain support should be treated carefully.

### Rules
- exact domain support is required now
- registrable-domain grouping is optional unless normalization policy is fully defined
- internal, malformed, reverse, and cloud-generated names must be handled explicitly
- do not assume public-suffix extraction is trivial for every observed name

If implemented in this phase, registrable-domain support should be clearly documented and well tested.

---

## Performance Guardrails

Performance is not a final polish phase. It is a design-time constraint.

Every change in this phase must account for:

- added write cost
- added query cost
- backfill cost
- page latency on large tables
- impact of concurrent ingest + UI traffic

### Required discipline
- use indexes deliberately
- prefer bounded queries and rollups already present in current schema
- avoid N+1s
- avoid full historical scans in hot pages
- validate performance as part of each feature, not only at the end

---

## Retention Model

The docs and implementation must explicitly acknowledge retention:

- raw DNS in `dns_events` and `dns_event_answers` is pruned
- aggregate host-domain associations remain
- near-term DNS UX must work with that reality

This means:
- some views are recent-window views by nature
- aggregate domain history may outlive raw DNS detail
- any new feature must state whether it depends on raw DNS history or aggregate history

---

## Decision Points Deferred to Future Architecture Work

This phase does **not** require immediate resolution of the following:

- whether to introduce a first-class `domains` table
- whether to introduce `dns_observations`
- whether to introduce device-domain or domain-host rollup tables
- whether to persist attribution confidence
- whether to build a generalized suppression policy engine

Those belong in a separate future-architecture document.

---

## Acceptance Criteria for This Plan

## Current-state grounding
- docs and implementation clearly acknowledge current agent + Rails pipeline
- no near-term task assumes normalized domain tables already exist

## DNS-centric UX
- operators can more easily search and inspect domain-related activity
- domain-centric pivots are clearer in the UI

## Host page
- host pages show better associated-domain information

## Device page
- device pages show useful DNS/domain activity

## Search
- search supports improved domain-related filtering
- hidden-by-default local-local internal app traffic for configured app-port range is available

## Noise handling
- internal app/control-plane traffic is preserved but can be hidden by default in targeted list views

## Performance
- features are implemented with performance validation as part of the work

---

## Non-Goals

Do not treat these as required for this phase:

- full normalized-domain redesign
- generalized presentation suppression engine
- persisted attribution confidence model
- graph visualization
- full reputation scoring
- complete DoH-detection subsystem
- replacement of current denormalized model

---

## Implementation Philosophy

- build on the shipped system
- improve operator workflows first
- preserve truth, hide noise where appropriate
- keep changes incremental
- let future architecture work be justified by real pain, not theoretical elegance