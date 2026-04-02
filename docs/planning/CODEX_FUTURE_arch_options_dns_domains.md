# CODEX FUTURE ARCHITECTURE OPTIONS: DNS, Domains, Attribution, and Suppression

## Purpose

This document is not the near-term implementation roadmap.

It records future architecture options that may become worthwhile if the current denormalized NetMon DNS/domain model starts limiting product value, operator workflows, or performance.

These are options, not immediate commitments.

---

## Current Baseline

Today the real system is centered on:

- Go agent DNS parsing and event emission
- Rails persistence into:
  - `dns_events`
  - `dns_event_answers`
- denormalized flow attribution in:
  - `connections.last_domain`
  - `connections.last_domain_observed_at`
- aggregate host-domain history in:
  - `remote_host_domains`

This model may remain sufficient for quite a while.

Future architecture work should only happen if current pain justifies it.

---

## Decision Trigger Questions

Do not start a larger redesign until we can answer yes to one or more of these:

1. Is current string-based domain search too slow or too awkward?
2. Are host/device/domain pivots hard to implement cleanly with current tables?
3. Is `remote_host_domains` too lossy or too narrow?
4. Is raw DNS pruning creating product gaps that current aggregates cannot fill?
5. Is connection attribution too hard to evolve without richer relational structure?
6. Are operators asking questions that the current schema cannot answer without ugly or slow queries?
7. Is suppression logic getting too fragmented to manage cleanly?

If the answer is mostly "no," keep improving the current model.

---

## Future Option A: Add a First-Class `domains` Table

## Motivation
A normalized domain record can make domain-first UX and future rollups cleaner.

## Possible shape
`domains`
- `fqdn`
- `registrable_domain`
- `first_seen_at`
- `last_seen_at`
- counters / cached stats as justified

## Benefits
- canonical key for domain pages
- easier exact vs registrable-domain grouping
- cleaner associations to future rollups
- less scattered string handling

## Costs
- migration complexity
- write-path overhead if updated at ingest
- backfill work
- coexistence with existing string-based fields during migration

## Use only if
- current string-based domain UX becomes too messy
- domain-first workflows become central enough to justify the cost

---

## Future Option B: Add a Derived `dns_observations` Table

## Motivation
Current raw DNS is stored in `dns_events` + `dns_event_answers`, but many operator queries may eventually want a flattened analytics-friendly form.

## Possible shape
`dns_observations`
- observed_at
- client_ip
- optional device_id
- qname
- registrable_domain
- answer_ip
- qtype
- rcode
- source
- dns_event_id

## Benefits
- easier recent DNS search
- easier domain/device/IP pivots
- clearer retention strategy if used as summarized history
- less awkward joining of raw DNS event + answer rows

## Costs
- write amplification
- backfill complexity
- retention policy complexity
- risk of duplicating truth if not clearly positioned as derived

## Use only if
- current DNS queries become awkward or slow enough to justify a derived table

---

## Future Option C: Device-Domain and Domain-Host Rollup Tables

## Motivation
If host pages, device pages, and domain pages need fast historical views, dedicated rollups may become worthwhile.

## Candidate rollups
### `device_domains`
- device/client identity -> domain history

### `domain_remote_hosts`
- domain -> remote host/IP history

## Benefits
- fast pages and summaries
- cheaper aggregation over large history
- easier domain-first and device-first pivots

## Costs
- more write complexity
- more backfills
- consistency maintenance
- more choices about retention and rebuild strategy

## Use only if
- current pages become too slow or too awkward without dedicated rollups

---

## Future Option D: Persisted Attribution Confidence

## Motivation
Not all domain matches are equally trustworthy, especially with CDNs/shared IPs.

## Possible model
A persisted confidence field for flow attribution:
- `strong`
- `medium`
- `weak`
- `none`

## Benefits
- more honest UI
- better filtering for operators
- clearer distinction between strong per-device matches and weaker aggregate matches

## Risks
- easy to define badly
- can create false precision
- requires exact semantics:
  - evidence rules
  - recency windows
  - upgrade/downgrade behavior
  - persistence policy

## Use only if
- current operator workflows are suffering from ambiguous or misleading domain attribution
- exact semantics can be written tightly enough to implement consistently

---

## Future Option E: Generalized Suppression / Presentation Policy Engine

## Motivation
As the app grows, we may want configurable logic for:
- hide by default in UI
- never alert
- reduce score
- classify as control-plane/internal
- exempt from certain dashboards or searches

## Important distinction
These are not the same behavior and should not be blurred together.

Potential rule actions could include:
- presentation hiding
- anomaly suppression
- alert suppression
- tagging/classification
- score adjustment

## Benefits
- consistent noise-management across surfaces
- more operator control
- fewer ad hoc filter hacks

## Costs
- substantial subsystem complexity
- indexing and query-planning implications
- rule precedence and auditability
- UI for rule management
- migration from current narrow suppression logic

## Use only if
- current narrow suppression + UI filter approach becomes insufficient

---

## Future Option F: Registrable-Domain-First Grouping

## Motivation
Operators often care about domain families, not only exact FQDNs.

Examples:
- `chatgpt.com`
- `ab.chatgpt.com`
- `api.github.com`
- `copilot-telemetry.githubusercontent.com`

## Benefits
- better grouping
- less fragmentation in UI
- more human-readable summaries

## Risks
- public-suffix handling is not trivial
- internal names, reverse names, malformed names, and CDN-generated names need policy
- bad grouping can be misleading

## Use only if
- normalization policy is explicit and tested
- operator benefit is clear enough to justify the added complexity

---

## Future Option G: Domain Pages as First-Class Product Objects

## Motivation
If operators increasingly think in domains, not just hosts and flows, a first-class domain object/page may become central.

## Potential product value
- domain as investigation entry point
- domain -> IP history
- domain -> device usage
- domain -> attributed flows
- domain family grouping
- "new domains" views

## Costs
- easier if normalized domain records exist
- harder to do well if every page recomputes from string fields

## Use only if
- the lightweight/current-architecture domain UX proves valuable and more is clearly needed

---

## Future Option H: Historical Summaries That Survive Raw DNS Pruning

## Motivation
Raw DNS is pruned. At some point product value may require richer historical summaries than `remote_host_domains` alone.

## Options
- longer-lived derived DNS summary table
- domain-host rollups
- device-domain rollups
- registrable-domain historical counts

## Benefits
- richer history with bounded storage
- domain/device/host history beyond raw DNS retention

## Costs
- summary maintenance
- definition of what is worth keeping
- backfill/rebuild complexity

## Use only if
- product needs exceed what retained aggregates can answer today

---

## Architecture Principles for Any Future Redesign

If a larger redesign is pursued later, it should follow these rules:

1. **Current system baseline first**
   - do not pretend future tables already exist
2. **Agent-aware design**
   - Go agent remains a first-class part of correctness
3. **Retention explicitness**
   - every table has a clear retention/rebuild policy
4. **Performance at design time**
   - write amplification and query cost must be justified
5. **Incremental migration**
   - avoid big-bang schema rewrites
6. **Preserve truth**
   - avoid deleting raw evidence purely for presentation reasons
7. **Separate semantics**
   - hidden-by-default, anomaly suppression, alert suppression, and tagging are distinct
8. **No decorative confidence**
   - only persist confidence if rules are exact and operationally useful

---

## Future Evaluation Checklist

Before adopting any future architecture option, answer:

- what operator problem does this solve that current architecture cannot solve cleanly?
- can the same problem be solved with lighter current-architecture improvements first?
- what is the write-path cost?
- what is the backfill strategy?
- what is the retention strategy?
- what indexes are required?
- what pages get materially faster or more useful?
- what migration complexity does it create?
- how will correctness be validated against current behavior?

---

## Recommended Future Sequence If Redesign Becomes Necessary

If future evidence justifies heavier architecture work, the likely safest order is:

1. codify current behavior and performance baselines
2. decide exact problem being solved
3. add the smallest justified normalized structure
4. backfill incrementally
5. dual-read or migrate targeted pages
6. measure ingest + page performance
7. only then consider further normalization

Do not start by adding every possible normalized table at once.

---

## Bottom Line

The current NetMon system may not need a major DNS/domain redesign yet.

The right near-term move is to improve DNS-centric UX on the current architecture.

This document exists so that, if future pain justifies it, architectural options are already thought through without confusing them with the immediate roadmap.