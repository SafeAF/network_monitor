# Critique of `CODEX_PLAN-dns_ux_improvements.md` and `CODEX_STEPS_dns_ux_improvements.md`

## Purpose

This document reviews the revised DNS UX planning docs for:

- architectural fit with the current NetMon system
- implementation feasibility
- sequencing
- hidden assumptions
- performance and operational risk
- where the plan is strong versus where it still needs tightening

Files reviewed:

- `docs/planning/CODEX_PLAN-dns_ux_improvements.md`
- `docs/planning/CODEX_STEPS_dns_ux_improvements.md`

---

## Overall Assessment

This revision is much better than the earlier DNS/domain plan.

The biggest improvement is that it now starts from the architecture that actually exists:

- Go agent as DNS source of truth
- Rails ingest into `dns_events` and `dns_event_answers`
- denormalized flow attribution via `connections.last_domain`
- remote-host aggregation via `remote_host_domains`
- raw DNS pruning with aggregate associations retained

That makes the plan directionally credible.

It is also better scoped:

- it avoids forcing an immediate normalized-domain redesign
- it treats UX and operator workflow as the near-term goal
- it separates UI default hiding from broader suppression/alert semantics

The remaining issues are mostly about precision, measurability, and a few hidden implementation risks.

---

## What The Revised Plan Gets Right

## 1. It uses the current architecture instead of arguing with it

This is the biggest correction from the earlier plan.

Good:

- it does not assume `domains`, `dns_observations`, or domain rollup tables exist
- it explicitly works from `dns_events`, `dns_event_answers`, `connections.last_domain`, and `remote_host_domains`
- it acknowledges the Go agent and event timing as first-class concerns

This makes the plan feasible as an incremental product plan rather than a speculative redesign.

---

## 2. It correctly narrows the immediate goal to UX and operator workflows

The plan is stronger because it asks practical questions:

- what domains has a device gone to?
- what IPs have been associated with a domain?
- what domains are associated with a host?
- how do we hide noisy internal traffic without deleting truth?

That is a good product framing. It is more grounded than leading with schema.

---

## 3. It handles suppression semantics more carefully

The explicit distinction between:

- UI default hiding
- anomaly suppression
- alert suppression
- internal/control-plane tagging

is correct and important.

That distinction should survive into implementation exactly as written.

---

## 4. It recognizes performance as a design-time concern

This is also a major improvement.

Given the system’s real-world behavior, any plan that pushes performance to the end would be suspect.

The revised docs correctly treat:

- query shape
- index use
- bounded windows
- ingest/UI contention

as primary design constraints.

---

## Main Critiques

## 1. The plan still says “device page improvements” more confidently than the current app supports

The desired device-page work is reasonable, but it is underspecified relative to current data reality.

Problem:

- current DNS truth is often keyed by `client_ip`
- current connection truth is keyed by `src_ip`
- device identity depends on how reliably `devices.ip` maps to the active client
- the plan asks for:
  - recent domains
  - top domains
  - DNS servers used
  - unattributed flows

Those are feasible, but only if the page semantics are explicit:

- are these “for this device record” or “for current traffic seen from this IP”?
- what happens if a device record exists but DNS was observed only by IP?
- what is the time window for “top domains”?

Critique:

- the plan is directionally right, but it understates the identity-quality problem

Recommended rewrite:

- define device-page DNS sections as IP-grounded unless/until device identity is stronger
- make “top domains” and “recent domains” explicitly bounded-window features

---

## 2. The lightweight domain entry point is good, but its backing data needs clearer semantics

The plan wisely avoids forcing a `domains` table, but the domain-centric entry point still needs precise data-source labeling.

Problem:

- a domain view could be assembled from:
  - recent connections where `last_domain = ?`
  - `remote_host_domains`
  - recent raw DNS within retention
- those sources do not mean the same thing

Example:

- `remote_host_domains` may outlive raw DNS detail
- `connections.last_domain` reflects only attributed flows
- raw DNS within retention may show queries that never turned into visible attributed connections

Critique:

- the plan mentions labeling results, which is good
- but this needs to be treated as a hard requirement, not a UI nice-to-have

Recommended rewrite:

- specify the page sections by provenance:
  - recent attributed connections
  - remote-host aggregate associations
  - recent raw DNS, if available
- avoid presenting them as one blended “truth” bucket

---

## 3. The plan should be more explicit about what “exact domain search” means

The steps call for exact-domain search improvements, but the current app already has substring search on:

- `connections.last_domain`
- `remote_host_domains.domain`

Problem:

- “better exact-domain search” can mean multiple things:
  - exact equality only
  - exact plus substring
  - exact match with a separate contains filter
  - normalized lowercased exact matching

Critique:

- without being explicit, the implementation could drift into “still mostly substring search but with different copy”

Recommended rewrite:

- define search modes precisely:
  - exact domain
  - contains
  - maybe suffix or registrable-domain later
- define expected query shape and matching behavior

---

## 4. The host-page improvement step is feasible, but the current controller/query path may not scale without care

Host-page domain improvements are one of the strongest parts of the plan because the data already exists.

Problem:

- current host show already does several per-page queries
- additional “recent devices involved”, “seen count”, or richer connection summaries can become expensive quickly
- especially if implemented by reconstructing evidence from `dns_events` or large `connections` scans per request

Critique:

- the plan says “if derivable cheaply,” which is good
- but “cheaply” should be made concrete

Recommended rewrite:

- prefer `remote_host_domains` as the primary source for host-domain summaries
- treat any join back to raw DNS or large connection history as bounded and optional
- define a hard cap on rows and lookback windows for host detail enrichments

---

## 5. Step 6 may duplicate or conflict with the hide-state filtering that already exists

The plan proposes UI-level hiding for local-local traffic on ports `3000..3010`.

That is a reasonable operator goal, but the app already has:

- state-based hide filters on the connections/dashboard surfaces

Problem:

- port-based default hiding is a different mechanism from state-based hiding
- the plan does not say how they combine

Possible bad outcomes:

- users are confused about why a row is hidden
- multiple hiding mechanisms stack invisibly
- views behave differently without clear explanation

Recommended rewrite:

- define how port-based hidden-by-default logic interacts with:
  - `hide_states[]`
  - `only_new`
  - existing search filters
- require a visible reason or explanatory copy when rows are hidden by policy defaults

---

## 6. Registrable-domain support is framed cautiously, but still not yet actionable

The plan correctly says registrable-domain grouping is optional and must be explicit.

That is good.

What is still missing:

- whether phase 1 should implement it at all
- what library or policy will be used
- whether PTR names, internal names, and malformed names are excluded or passed through

Critique:

- the caution is correct
- but the current wording still leaves enough ambiguity for implementation churn

Recommended rewrite:

- make a concrete decision:
  - either exact-domain only for this phase
  - or exact-domain plus tightly scoped registrable grouping with documented normalization behavior

My recommendation:

- exact-domain only for this phase
- defer registrable-domain grouping unless a specific operator workflow requires it now

---

## 7. Performance validation needs measurable thresholds, not only good intentions

The plan correctly says to measure performance on each slice.

Problem:

- it does not define success thresholds

Without thresholds, “validate performance” becomes subjective.

Recommended rewrite:

- define budgets for common pages and query paths, for example:
  - search index pages should render within a target latency on production-like data
  - host detail should stay under a target latency with current row counts
  - new domain-centric views must avoid raw DNS joins unless bounded to a recent window
- also define what to record:
  - response time
  - SQL count
  - whether hot queries use indexes
  - row counts returned

This plan will be much more executable if those guardrails are concrete.

---

## 8. The plan is good at avoiding a schema redesign, but it should say when the current architecture is no longer enough

Step 12 asks whether future architecture work is needed.

That is the right instinct.

What is missing:

- explicit triggers for escalation

Recommended rewrite:

- state conditions that would justify moving beyond the current model, such as:
  - string-based domain search becomes too slow or ambiguous
  - device-page domain summaries require repeated expensive aggregation
  - raw DNS pruning removes detail needed for domain UX
  - operators need stable domain entities, not just strings

This would make the “reassess later” step more objective.

---

## Feasibility By Step

## Step 0: Re-baseline current pipeline

Feasibility: high

Comments:

- necessary
- low risk
- should probably produce a short doc artifact, not just comments

---

## Step 1: Define UX gaps precisely

Feasibility: high

Comments:

- good product discipline
- should use real operator questions and example workflows

---

## Step 2: Improve domain search on current model

Feasibility: high

Comments:

- already close to current capabilities
- likely the fastest high-value improvement
- needs precise semantics on exact vs substring search

---

## Step 3: Lightweight domain-centric entry point

Feasibility: medium-high

Comments:

- feasible without schema redesign
- risk is semantic confusion if data sources are blended carelessly
- performance is manageable if windows are bounded and sources are explicit

---

## Step 4: Host-page improvements

Feasibility: high

Comments:

- current data supports this well
- likely a strong ROI improvement
- should stay anchored in `remote_host_domains`

---

## Step 5: Device-page improvements

Feasibility: medium

Comments:

- useful, but more sensitive to identity ambiguity
- feasible if framed as IP-based recent behavior
- risky if presented as stronger device identity than current data deserves

---

## Step 6: UI-level hiding for local app traffic

Feasibility: high

Comments:

- straightforward query/UI work
- main risk is conflicting semantics with existing hide-state filters

---

## Step 7: Clarify suppression semantics

Feasibility: high

Comments:

- important and overdue
- mostly documentation and naming discipline

---

## Step 8: Registrable-domain support

Feasibility: medium-low for this phase

Comments:

- feasible technically
- not clearly necessary yet
- easy place to create complexity without proven value

---

## Step 9: Add recent DNS/domain summaries

Feasibility: medium-high

Comments:

- good if kept small
- should be chosen based on operator value, not completeness

---

## Step 10: Validate performance along the way

Feasibility: high

Comments:

- must be concrete and repeatable
- should name the tools and measurements expected

---

## Step 11: Update documentation

Feasibility: high

Comments:

- necessary
- should reflect actual data provenance and retention

---

## Step 12: Reassess future architecture

Feasibility: high

Comments:

- good discipline
- should have explicit escalation criteria

---

## Missing Or Underdeveloped Areas

## 1. No explicit plan for saved queries or route integration if a domain entry point is added

If a new domain-oriented entry point is added, the plan should decide:

- is it part of `/search`
- is it a standalone page
- does it support saved queries
- how it fits the top-level navigation

This does not need a full decision now, but it should not be left entirely implicit.

---

## 2. No explicit plan for empty/uncertain-result UX

Domain attribution is incomplete by nature.

The UX will need to handle cases where:

- raw DNS is gone due to pruning
- host association exists but recent connections do not
- connections exist but no matching domain attribution exists
- DoH/bypassed local DNS means there is no domain evidence

The plan should say how those states are explained to the operator.

---

## 3. No explicit note about how anomaly pages benefit from DNS UX work

The revised plan mentions dashboards, hosts, devices, and search more than anomalies.

That is mostly fine, but anomaly investigation is one of the core operator workflows.

There may be small high-value additions such as:

- better domain display in anomaly rows
- quick pivots from anomaly to domain-oriented search

This does not need to become a major workstream, but it should not be forgotten.

---

## 4. No clear decision rule for when to use raw DNS versus aggregate history

This is one of the most important implementation questions.

The plan acknowledges retention, but future implementers still need a rule of thumb like:

- use `remote_host_domains` for durable host-domain associations
- use `connections.last_domain` for recent attributed flows
- use raw DNS only for recent-window drilldown or debugging

That principle should be written explicitly.

---

## Suggested Tightening Changes

Before execution, I would tighten the plan in these ways:

1. Define exact-domain search semantics precisely.
2. Define the domain entry point sections by data provenance.
3. Frame device DNS views as IP-grounded unless identity guarantees improve.
4. Explain how local-port hidden-by-default logic interacts with existing hide-state filters.
5. Add measurable performance budgets per page/query type.
6. Defer registrable-domain support unless a concrete immediate use case justifies it.
7. Add explicit escalation criteria for when the current string-based architecture is no longer enough.
8. Add empty/uncertain-result UX expectations for missing attribution or pruned DNS.

---

## Bottom Line

These revised planning docs are credible and mostly feasible.

They are a substantial improvement because they now fit the actual system and avoid prematurely forcing a normalized-domain migration.

The main remaining work is not a major architectural correction. It is tightening:

- definitions
- performance budgets
- data-provenance semantics
- UX behavior when attribution is partial or missing

If those are clarified, this is a solid near-term roadmap. My main caution is to keep the phase focused on:

- exact-domain UX
- host-page improvement
- carefully framed device-page DNS visibility
- explicit UI-level noise hiding

and not let registrable-domain work or over-ambitious domain-page behavior expand the scope too early.
