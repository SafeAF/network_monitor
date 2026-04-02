# Issues With `CODEX_plan_dns_domains_and_suppressions.md` and `CODEX_steps_dns_domains_and_suppressions.md`

## Purpose

This document records where the existing DNS/domains/suppressions planning docs no longer match the shipped NetMon system, where they are ambiguous, and where following them literally would create unnecessary churn or architectural conflict.

It is intended as input for a future rewrite of:

- `docs/planning/CODEX_plan_dns_domains_and_suppressions.md`
- `docs/planning/CODEX_steps_dns_domains_and_suppressions.md`

The goal is not to reject the original direction outright. Some ideas are still useful. The goal is to make clear what is obsolete, what is incomplete, and what must be rewritten around the system that actually exists today.

---

## Short Summary

The two planning docs describe a larger normalized-domain redesign than the product actually implemented.

Today the real system is:

- raw DNS stored in `dns_events` and `dns_event_answers`
- flow attribution stored denormalized on `connections.last_domain` and `connections.last_domain_observed_at`
- remote-host domain history stored in `remote_host_domains`
- suppressions and allowlists used primarily in anomaly scoring and a few UI flows, not as a generalized presentation-layer rule engine
- a Go router agent that emits `dns_response` and `flow` events, with Rails ingesting and correlating them

The planning docs assume:

- a first-class `domains` table
- a derived `dns_observations` analytics table
- normalized rollups like `device_domains` and `domain_remote_hosts`
- flow attribution confidence columns
- a broad presentation suppression engine
- new `/domains` pages and domain-centric UI pivots

That planned architecture was only partially realized. The docs now mix valid aspirations with assumptions that are false in the current codebase.

---

## Current System Reality That The Docs Must Acknowledge

Before listing issues, the rewrite should be grounded in the current architecture:

- DNS ingest is driven by the Go agent parsing `dnsmasq` logs and emitting `dns_response` events.
- Rails persists those into `dns_events` and `dns_event_answers`.
- Flow attribution happens at ingest/backfill time and currently populates:
  - `connections.last_domain`
  - `connections.last_domain_observed_at`
  - `remote_host_domains`
- There is no normalized `domains` table.
- There is no `dns_observations` table.
- There is no `device_domains` table.
- There is no `domain_remote_hosts` table.
- There is no `last_domain_id`, `domain_confidence`, or `last_registrable_domain` on `connections`.
- Existing `suppression_rules` are much narrower than the proposed generalized rule system.
- Search and UI pages already support some domain filtering through string fields and `remote_host_domains`.
- DNS retention has already been implemented as raw-DNS pruning via `netmon:dns_prune`, while leaving aggregate domain associations intact.

Any rewrite that does not start from those facts will be misleading.

---

## Major Issues

## 1. The plan assumes a normalized domain architecture that does not exist

Both docs treat `domains`, `dns_observations`, `device_domains`, and `domain_remote_hosts` as the near-term target architecture.

Problem:

- none of those tables exist
- no migration path toward them is currently active
- current features were built on top of `dns_events`, `dns_event_answers`, `connections.last_domain`, and `remote_host_domains`

Why this matters:

- the plan reads as if the system is halfway through a normalized-domain migration
- in reality, the shipped product is still string-centric for attribution and remote-host association

Rewrite implication:

- the new docs must explicitly distinguish:
  - current architecture
  - desired future normalized architecture, if still wanted
- they should not describe the normalized model as if it is already the established direction of the live product

---

## 2. The docs understate how much value already exists in the current denormalized system

The current-state sections frame existing DNS/domain support as weak or preliminary.

That is now inaccurate.

What actually exists today:

- agent-side DNS parsing for `query`, `forwarded`, `reply`, `cached`, `NXDOMAIN`, `NODATA`, `CNAME`, PTR, and interleaved A/AAAA cases
- Rails ingest and backfill paths that can update recent flows after DNS arrives
- host-page domain sections
- host search filtering by associated domain
- connection search filtering by `last_domain`
- remote-host domain history retention even after raw DNS pruning

Why this matters:

- the rewrite should not pretend the system is still only "best-effort enrichment"
- the next design should build on what works instead of restarting from scratch conceptually

Rewrite implication:

- include a section titled something like `What Already Exists`
- list the actual shipped DNS/domain behaviors before proposing new work

---

## 3. The plan ignores the Go agent as the primary DNS source of truth

The plan talks about `dns_events` and `dns_event_answers` as if the main work is relational modeling on the Rails side.

Problem:

- the critical correctness and coverage issues were in the Go agent parser/correlator
- actual product behavior depends heavily on:
  - `dnsmasq` log formats
  - agent-side correlation
  - event batching and delivery timing
  - conntrack event timing (`NEW`, `DESTROY`, etc.)

Why this matters:

- many domain-attribution failures were not schema problems
- they were parsing, correlation, timing, and ingest-order problems

Rewrite implication:

- the rewrite must include agent responsibilities as first-class architecture
- it must document that domain correctness depends on both:
  - router-side DNS visibility
  - Rails-side persistence/correlation

---

## 4. The plan proposes confidence-aware attribution without a concrete operational definition

The docs propose `strong`, `medium`, `weak`, `none`.

Problem:

- no current schema or UI supports this
- the heuristics are not defined tightly enough for implementation consistency
- there is no discussion of recency windows, conflicting evidence, or how confidence affects backfill versus live attribution

Why this matters:

- "confidence" sounds useful but becomes hand-wavy unless:
  - it is derived deterministically
  - stored consistently
  - queryable without expensive recomputation

Rewrite implication:

- either:
  - specify exact rules and storage semantics, or
  - remove confidence from the near-term plan and treat it as later work

At minimum the rewrite should answer:

- what exact evidence yields each level
- whether confidence is persisted or computed
- how later DNS evidence can upgrade or downgrade a connection
- what happens with shared CDN IPs, PTR-only evidence, or no same-device match

---

## 5. The suppression design is far broader than the current suppression system

The plan frames suppressions as a generalized operator-facing presentation engine covering dashboards, hosts, devices, connections, anomalies, and global views.

Problem:

- the current `suppression_rules` table is small and purpose-built
- current suppression behavior is mostly inside anomaly scoring / alert logic, not a generalized query-time presentation layer
- broad suppression matching across IPs, subnets, devices, domains, local/local logic, and port ranges would require a substantially different rule engine

Why this matters:

- the proposed suppression design is not a small extension
- it is a separate subsystem with query-planning, indexing, rule-precedence, auditability, and UI implications

Rewrite implication:

- the rewrite must explicitly say whether the goal is:
  - anomaly-only suppression
  - search/dashboard presentation suppression
  - both, with separate mechanisms

It should also separate:

- "never alert on this"
- "hide by default in list views"
- "reduce anomaly score weight"
- "tag as internal/control-plane"

Those are distinct actions and should not be blurred together.

---

## 6. The docs do not reflect the current internal-noise handling that already exists in UI filters

The old docs treat hidden-by-default internal noise as future work.

Problem:

- the main dashboard/connections surface already has hide-state filters
- users can now selectively hide `TIME_WAIT`, `DESTROY`, `SYN_SENT`, and `CLOSE`
- the plan still centers a future suppression engine as if nothing has been implemented yet

Why this matters:

- there is already a practical UI-level noise-management mechanism
- future planning should decide whether to evolve that mechanism or replace it, not ignore it

Rewrite implication:

- distinguish:
  - current explicit state-based UI filtering
  - future rule-based automatic suppression, if still desired

---

## 7. The migration/step sequencing no longer matches the product’s actual evolution

The steps imply a clean progression:

1. normalized tables
2. backfills
3. rollups
4. new domain pages
5. suppression engine

Problem:

- the actual product evolved differently
- operational fixes happened first:
  - agent DNS parser fixes
  - CNAME/PTR/NODATA handling
  - backfill of late-arriving DNS to recent connections
  - `NEW` conntrack events
  - dashboard/query performance work

Why this matters:

- the real dependency order turned out to be:
  - correctness and completeness of ingest
  - timing/correlation fixes
  - performance
  - only then richer modeling/UI

Rewrite implication:

- future steps should begin with:
  - verifying DNS capture coverage
  - measuring attribution hit rate
  - preserving performance on ingest and UI pages
- not with a large schema migration by default

---

## 8. The plan does not address the performance cost of the proposed normalized design

The docs mention "no N+1s" and "avoid giant table scans" but not the real performance risks.

Missing concerns:

- extra write amplification on ingest
- more contention on SQLite if the live system still runs that way
- backfill cost on large DNS history
- duplicate rollup maintenance across raw DNS, connections, and host associations
- query complexity if both legacy and normalized paths coexist for a long migration

Why this matters:

- performance was already a major production problem
- adding `domains`, `dns_observations`, `device_domains`, and `domain_remote_hosts` without an ingest/write-path plan could regress the app badly

Rewrite implication:

- every proposed schema addition should specify:
  - write path
  - backfill strategy
  - idempotency
  - indexes
  - expected query benefit
  - expected ingest overhead

---

## 9. Domain-page work is described as if it is clearly the next product priority

The docs devote major attention to `/domains` pages and domain-centric pivots.

Problem:

- the current product has gotten value from:
  - domain display in connections
  - host page associations
  - host search filters
- but there is not yet evidence in the planning docs that standalone `/domains` pages are the next highest-value step

Why this matters:

- domain pages may be valuable
- but they are not free, and they pull the architecture toward normalized-domain tables

Rewrite implication:

- the rewrite should separate:
  - must-have operator problems
  - nice-to-have domain-centric UX

Questions the rewrite should answer:

- what operator question cannot be answered today without `/domains`
- can that question be solved with lighter enhancements first

---

## 10. The steps assume registrable-domain extraction is straightforward

The plan repeatedly uses "registrable domain" and eTLD+1 grouping.

Problem:

- there is no current shared normalization utility or public suffix integration
- internal names, PTR names, cloud/CDN names, and malformed/mixed DNS data complicate eTLD+1 semantics
- the docs do not define policy for names that are:
  - internal only
  - single-label
  - reverse-lookup names
  - invalid but observed

Why this matters:

- bad registrable-domain logic would create poor grouping and misleading UI

Rewrite implication:

- the future doc should define normalization policy precisely, including failure behavior
- registrable-domain support should probably be framed as optional or phase-gated rather than assumed

---

## 11. The plan assumes more stable device identity than the current DNS pipeline actually guarantees

Several proposed rollups rely on `device_id`.

Problem:

- current DNS correlation is often keyed by `client_ip`
- device resolution can be indirect or missing
- using `device_id` as a strong relational anchor in `dns_observations` or `device_domains` would require a clear policy for:
  - missing device records
  - IP churn
  - late device creation

Rewrite implication:

- the rewrite should not casually require `device_id` everywhere
- it should define when `client_ip` is the source of truth and when `device_id` is trustworthy enough for rollups

---

## 12. The docs do not incorporate the implemented DNS pruning strategy

The old plan assumes long-term buildout from raw DNS history.

Problem:

- the actual system now prunes raw `dns_events` and `dns_event_answers` older than 30 days
- aggregate host-domain associations are intentionally preserved

Why this matters:

- this changes what "historical DNS" means
- any future normalized table design must state whether it is:
  - also pruned
  - retained all-time
  - summarized before pruning

Rewrite implication:

- retention policy must be explicit per table, not implied

---

## 13. The acceptance criteria are no longer a good fit for an incremental rewrite

The current acceptance sections are large and compound:

- normalized domains exist
- dns observations populated
- rollups exist
- confidence exists
- domain pages exist
- suppressions are configurable

Problem:

- this bundles multiple major subsystems together
- it makes partial success hard to evaluate

Rewrite implication:

- acceptance should be broken into narrower milestones, for example:
  - DNS correctness coverage
  - connection attribution quality
  - host/domain UI usefulness
  - suppression semantics
  - performance safety

---

## Specific Issues In `CODEX_steps_dns_domains_and_suppressions.md`

## Step 1 through Step 5 are effectively a forked architecture plan

These steps define new domain tables, new rollups, and new connection attribution columns before proving they are necessary.

Issue:

- this is not a small additive change
- it would introduce a second attribution architecture next to the one that actually powers the app today

Rewrite recommendation:

- reframe these steps as an optional future normalization track, not the baseline implementation plan

---

## Step 6 conflates multiple suppression goals

The step mixes:

- hide by default
- de-noise rare-port surfaces
- never alert
- internal control-plane tagging

Issue:

- those are different mechanisms with different consumers

Rewrite recommendation:

- split suppression into separate workstreams or at least separate rule actions with clear consumers

---

## Step 7 through Step 13 are too UI-heavy relative to current technical gaps

The steps move quickly into domain pages, device pages, dashboards, saved queries, and migrations away from `remote_host_domains`.

Issue:

- current higher-risk work is still around attribution quality, retention semantics, and query performance

Rewrite recommendation:

- put product/UI expansion after:
  - correctness metrics
  - performance validation
  - a decision on whether normalized domain tables are actually needed

---

## Step 14 is too late for performance work

The current steps place performance near the end.

Issue:

- performance in this system is not a cleanup phase concern
- it is a design-time constraint because ingest and UI share the same app/database resources

Rewrite recommendation:

- performance review should be attached to every major step, especially:
  - ingest writes
  - backfills
  - new query paths
  - UI index/show pages

---

## Step 15 documentation scope is too narrow

The step focuses on conceptual docs like exact vs registrable domain and suppression philosophy.

What is missing:

- agent log-shape assumptions
- DNS failure modes
- retention model
- late-DNS backfill behavior
- limitations from DoH/bypassed local DNS

Rewrite recommendation:

- documentation should cover operational reality, not only conceptual data-model ideas

---

## What Still Looks Valid

Not everything in the old docs is wrong. These ideas are still reasonable:

- preserve raw ingest instead of filtering away truth
- keep changes incremental and reviewable
- add tests with each schema/service change
- avoid breaking existing UI while migrating
- support domain filtering in operator views
- treat internal/control-plane noise as a presentation problem rather than data-deletion problem
- use backfills and idempotent jobs when introducing derived structures

Those parts should survive into a rewrite.

---

## Recommended Rewrite Structure

The future replacement docs should be organized around this order:

1. Current system baseline
   - what tables, services, and pages already exist
   - what the agent emits
   - what is already working

2. Known limitations
   - where attribution still fails
   - where string-based modeling hurts
   - what suppressions can and cannot do today

3. Decision points
   - do we actually want normalized domain tables
   - do we need standalone domain pages now
   - do we want presentation suppression, alert suppression, or both

4. If normalized domains are still desired
   - exact minimum schema additions
   - write/backfill cost
   - compatibility strategy
   - retention strategy

5. Performance guardrails
   - how to measure ingest cost
   - how to measure query cost
   - what counts as acceptable

6. UI/product increments
   - small improvements first
   - heavyweight new pivots later

---

## Concrete Questions The Rewrite Must Answer

Before replacing the old docs, the new version should explicitly answer:

- Is the next step to improve the current string-based model, or to replace it?
- Are `/domains` pages actually required now, or just desirable?
- Is `remote_host_domains` a legacy stopgap, or the intentional current aggregate model?
- Should suppressions affect:
  - anomaly scoring only
  - alert generation only
  - list-view visibility only
  - all of the above, with distinct semantics
- What evidence is sufficient for a "strong" domain match, and do we need persisted confidence at all?
- What historical data must survive raw DNS pruning?
- What performance budget is acceptable for:
  - ingest batches
  - connections page
  - search pages
  - host detail pages

---

## Bottom Line

These planning docs are now best treated as exploratory design notes, not an implementation-ready roadmap.

Their biggest issue is not that they were unreasonable. It is that they no longer describe the system we actually have, and they propose a larger architectural jump than current evidence justifies.

The rewrite should start from the shipped agent-plus-Rails DNS pipeline, the existing denormalized attribution model, the implemented pruning/backfill behavior, and the real performance constraints observed in production-like use.
