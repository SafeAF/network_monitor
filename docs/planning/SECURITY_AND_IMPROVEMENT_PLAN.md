# Security and improvement plan

Review date: November 11, 2026.

This review covers the Rails application, Go agent, ingestion contract, deployment files, and test configuration. The highest priorities are access control, stored cross-site scripting (XSS), and trustworthy ingestion. A LAN deployment still needs these protections: any compromised device that can reach the app currently has access to its investigation and alert-management functions.

This is a source review, not a penetration test or a completed dependency vulnerability scan. Deployed proxy, firewall, TLS, and scheduling settings were not inspected. At the initial review, only this plan was added. The status below records subsequent implementation work.

## Implementation status — November 12, 2026

Phase 1 has started. Changes are local and have not been deployed or committed. Findings below describe the original reviewed code; dashboard rendering and GitHub configuration have since moved.

Implemented in the first batch:

- **S1:** Fail-closed HTTP Basic authentication for operator HTML/JSON routes, separate administrator and optional reader credentials, administrator-only mutations, structured audit log entries without note values, and bounded names/notes/rule fields. Agent bearer authentication remains separate and uses constant-time comparison with a mandatory Bearer scheme. Production agent tokens must be at least 32 bytes.
- **S2:** Dashboard JavaScript moved into [modules](../../netmon/app/javascript/netmon/dashboard.js). Connection rows, drilldowns, top panels, and column controls now construct DOM nodes and set text/properties; no dashboard `innerHTML` sinks remain. URL path components are encoded. A restrictive CSP is enabled in report-only mode while other inline scripts/styles are inventoried.
- **S3, partial:** Agent configuration requires HTTPS unless `development_allow_insecure_http: true` is explicitly configured. Tokens shorter than 32 bytes are rejected. All ingest redirects are refused and normal certificate verification remains enabled. The sample config and Kamal secret wiring were updated. Per-router credentials, revocation, and overlapping rotation remain open.
- **S5, partial:** Probe GET is read-only; POST/DELETE require administrator authentication and normal browser CSRF checks. Probes require an observed literal IP and reject loopback, link-local, multicast, mapped IPv6, hostnames, and options. Child output/deadlines are bounded; cancellation uses a per-run marker checked by the running process. Atomic cross-worker deduplication and per-user/global quotas remain open; the existing cache-based state is not a concurrency guarantee.
- **O3, partial:** [CI](../../.github/workflows/ci.yml) and [Dependabot](../../.github/dependabot.yml) moved to the repository root. CI builds assets, runs RSpec, standalone Ruby security checks, real-browser rendering checks, Brakeman, RuboCop, Linux Go race tests/vet, and an agent build. Dependency advisory audits and production-image checks remain open. GitHub CI has not yet run on these local changes.

Configuration required before using the updated app:

- Set `NETMON_ADMIN_USERNAME` and `NETMON_ADMIN_PASSWORD` (at least 20 bytes). There are no default credentials or development bypass. Serve HTTP Basic only behind HTTPS outside local development; do not reuse the agent token as an operator password.
- Optionally set `NETMON_READER_USERNAME` and `NETMON_READER_PASSWORD` (at least 20 bytes). Readers can read telemetry but cannot mutate data or run/cancel probes. Reader variables must be wired separately if using Kamal.
- Set the same strong random `NETMON_API_TOKEN` / agent `auth_token` (at least 32 bytes), and configure an HTTPS `rails_base_url` with a valid certificate. The sample token is intentionally empty. The HTTP override permits plaintext development transport; it never disables HTTPS certificate verification.
- Audit entries go to application logs with actor, action, target, changed field names, request ID, time, and response status. Preserve these logs in the deployment. A durable before/after audit store is a later improvement.

Verification of this batch:

- `ruby test/security_utilities_test.rb`: **9 tests, 30 assertions passed**, including credential separation, IP restrictions, command output bounds, timeout after early stdout closure, and child cancellation.
- `node test/javascript/rendering_test.mjs`: **passed in isolated headless Chrome** using the actual rendering modules and hostile strings in connection fields, attributes, paths, drilldowns, and panels. This is a renderer browser test, not a complete Rails/browser end-to-end test.
- Ruby syntax checked for 27 touched/relevant files; JavaScript modules parsed successfully; changed Go files formatted with `gofmt`; Git whitespace checks passed.
- An isolated Windows test bundle was installed without changing the project Gemfile/lockfile. RSpec/Brakeman execution was blocked by Windows Application Control when loading native libraries. The verified portable Go executable was also blocked by that OS policy, so Go tests were not executed locally. These checks remain required in Linux CI before deployment.

Next work: resolve CI findings on Linux, complete remaining Phase 1 credential/probe controls and CSP rollout, then implement durable event identities, acknowledgements, atomic processing, and replay tests (R1/S4). No finding should be marked fully resolved solely because its first mitigation is present.

## Findings and recommended changes

### S1 — High: web UI and management actions have no application authentication

Evidence: [ApplicationController](../../netmon/app/controllers/application_controller.rb#L1) only applies browser-version checks. [Routes](../../netmon/config/routes.rb#L17) expose telemetry, device updates, incident acknowledgements, allowlists, and suppression creation. Their controllers do not require a signed-in user or check roles. Authentication is confined to the agent batch endpoint.

Impact: a client that can reach Rails can read network activity, change labels, acknowledge incidents, and create rules that reduce detection. Rails CSRF protection does not establish a user's identity; a direct client can obtain its own session and authenticity token.

Plan: require operator authentication for HTML and JSON routes; distinguish read access from alert/rule administration. For a small installation, an authenticating reverse proxy is a reasonable first containment step if direct access to Rails is blocked. Keep agent authentication separate. Record actor, time, target, and changes for acknowledgements and rule updates. Bound rule/name/note lengths.

Acceptance: anonymous reads and writes are rejected; readers cannot mutate rules or incidents; an agent credential cannot open operator pages; authorized changes create audit records.

### S2 — High: stored values become executable dashboard HTML

Evidence: the dashboard interpolates device names into an input attribute at [line 613](../../netmon/app/views/dashboard/index.html.erb), domains into link text and attributes at [line 593](../../netmon/app/views/dashboard/index.html.erb), and reverse-DNS/WHOIS values at [line 637](../../netmon/app/views/dashboard/index.html.erb). The resulting strings reach `innerHTML` at [line 701](../../netmon/app/views/dashboard/index.html.erb). Top panels also insert device labels into HTML at [line 1556](../../netmon/app/views/dashboard/index.html.erb). [DevicesController](../../netmon/app/controllers/devices_controller.rb#L8) accepts names without content restrictions. The [CSP initializer](../../netmon/config/initializers/content_security_policy.rb#L1) is entirely commented out.

Impact: a crafted stored name can execute JavaScript when an operator views the dashboard. Telemetry, DNS, and enrichment strings provide additional untrusted inputs. A device name containing HTML is a sufficient source-level reproduction path; exploitation through real DNS depends on resolver/log formatting and was not tested.

Plan: replace dynamic HTML templates with DOM creation, `textContent`, and property assignment such as `input.value`; encode URL path components and construct URLs with URL APIs. Review every `innerHTML` sink, including drilldowns and incident panels. Move inline dashboard JavaScript into maintained modules and introduce a restrictive CSP, initially in report-only mode. CSP supplements safe rendering.

Acceptance: browser tests persist markup and quote-containing names and ingest hostile metadata; refresh, detail panels, and drilldowns display literal text without creating executable elements or event handlers.

### S3 — High when HTTP is used: agent token and telemetry travel in cleartext

Evidence: [the checked-in sample config](../../netmon_config.yaml#L3) and [agent setup guide](../../netmon_agent/docs/AGENT_SETUP.md#L16) use HTTP. [Config validation](../../netmon_agent/internal/config/config.go#L111) only checks that URL and token are nonempty. The [HTTP client](../../netmon_agent/internal/httpclient/client.go#L211) sends a reusable bearer token. The sample also contains fixed placeholder token/salt values; their presence is not evidence of a leaked live credential.

Impact: on an observable or manipulated network path, tokens and DNS/flow activity can be captured or altered. Rails production SSL settings do not protect the initial plaintext request sent by the agent.

Plan: require HTTPS and certificate verification by default, with a clearly named development-only HTTP override. Reject placeholder credentials outside development; use strong random credentials. Add per-router credentials, revocation, overlapping rotation, and binding between credential and `router_id`. Use constant-time secret comparison as secondary hardening. Restrict redirects to the intended HTTPS origin. Add `NETMON_API_TOKEN` to deployment secret wiring: [deploy.yml](../../netmon/config/deploy.yml#L35) currently injects only `RAILS_MASTER_KEY`.

Acceptance: HTTP, invalid certificates, redirects outside the configured origin, missing credentials, and unauthorized router identities fail; valid HTTPS ingestion and credential rotation succeed.

### S4 — High with an agent credential: ingest can consume excessive resources

Evidence: [EventsController](../../netmon/app/controllers/api/v1/netmon/events_controller.rb#L5) accepts an unbounded event collection and arbitrary nonempty event types. Flow [IP fields](../../netmon/app/lib/netmon/agent_ingest.rb#L21) receive presence checks, not IP validation; ports, counters, and timestamps lack domain bounds. Each batch opens one database transaction. [Host enrichment](../../netmon/app/lib/netmon/agent_ingest.rb#L42) performs DNS and WHOIS inside that transaction, and [WHOIS execution](../../netmon/app/lib/netmon/host_enricher.rb#L68) has no application timeout.

Impact: a stolen credential, a noisy network, or malformed agent data can fill storage, occupy web workers, and extend SQLite write contention. Invalid IP strings also reach external utilities as arguments. Argument arrays avoid ordinary shell interpolation, but destination and option validation are still necessary.

Plan: enforce request byte limits at the proxy and application boundary, event-count and field-size limits, supported event types (including the agent's `firewall_drop` type), object/array shapes, literal IP addresses, valid port/protocol ranges, nonnegative bounded counters, and a documented timestamp/replay window. Add per-router quotas. Reject unknown types or explicitly classify them as raw-only; do not call them normalized successes. Move enrichment to bounded jobs outside write transactions, with deadlines, output limits, caching, and safe utility arguments.

Acceptance: oversized requests receive 413; invalid events receive structured errors; malformed event shapes never cause an unhandled 500; slow enrichment does not extend ingest transactions. Load tests show bounded memory and acceptable UI latency during ingestion.

### S5 — Medium: traceroute can be triggered through an unauthenticated GET

Evidence: [the route](../../netmon/config/routes.rb#L35) uses GET; [the action](../../netmon/app/controllers/remote_hosts_controller.rb#L69) enqueues work when `start` is present and accepts cancellation through query parameters. [TracerouteJob](../../netmon/app/jobs/traceroute_job.rb#L20) passes an unvalidated route parameter to the utility. Host detail views similarly invoke `geoiplookup` with the supplied value.

Impact: a reachable client can enqueue network probes to arbitrary accepted destinations, consume worker capacity, and trigger state changes through cross-origin GET requests. The current argument-array calls do not establish shell-command injection. String values beginning with options and arbitrary hostnames should still be excluded.

Plan: use authenticated, authorized POST/DELETE operations with CSRF protection for browser actions. Accept only literal IPs, require an explicit destination policy appropriate to LAN monitoring, deduplicate jobs atomically, and apply per-user/global concurrency and rate limits. Enforce child-process deadlines with termination and reaping; cancellation must stop work rather than only change a cached label. Keep result polling read-only.

Acceptance: GET never starts/cancels probes; anonymous requests, invalid destinations, options, and quota violations are rejected; timed-out and cancelled probes leave no running child process.

### R1 — High monitoring risk: rejection handling and replay can lose or corrupt data

Evidence: [EventsController](../../netmon/app/controllers/api/v1/netmon/events_controller.rb#L14) inserts raw data, then rescues per-event failures inside the outer transaction without a per-event rollback boundary. [DNS ingestion](../../netmon/app/lib/netmon/dns/ingest_event.rb#L15) returns nil on invalid input or errors, yet the controller increments `accepted`. The [existing request spec](../../netmon/spec/requests/api/netmon_events_spec.rb#L55) even expects malformed DNS plus a valid flow to report two accepted events. The [agent](../../netmon_agent/internal/httpclient/client.go#L230) discards response bodies, treating every 2xx as complete success, and [removes replayed spool files](../../netmon_agent/internal/httpclient/client.go#L263). Raw events have no event-identity uniqueness constraint.

Impact: rejected normalized events are silently abandoned; failures after early writes can leave partial normalized state. A timeout after server commit causes retry and duplicate raw events. Flow counters, per-minute connection counts, and reused flow tuples can be affected by duplicates or reordered live/replay delivery.

Plan: define stable event IDs and a durable acknowledgement contract before changing retry behavior. Atomically persist raw event identity and processing state; use per-event savepoints or an asynchronous durable inbox. Return per-event outcomes and separate retryable failures from permanent invalid input. Make normalized processing idempotent, retain retryable events, and put permanent failures in a bounded quarantine. Preserve order/version checks per flow so older replay cannot overwrite newer state. Add atomic spool writes using temporary files and rename, crash recovery, observable eviction, and corrupt-file quarantine so a bad oldest file cannot block all replay.

Acceptance: repeat a batch after a simulated commit-time timeout; raw identity, rollups, and incidents are unchanged by replay. A mixed batch reports accurate outcomes. Injected mid-event failures roll back that event. Partial rejection, corrupt spool files, restart during a write, and replay/live reordering do not silently lose valid events.

### R2 — High monitoring risk: the preferred agent path does not create incidents

Evidence: [AgentIngest](../../netmon/app/lib/netmon/agent_ingest.rb#L92) calculates and stores connection scores, but does not create `AnomalyHit` or `Incident` records. That workflow exists in [ReconcileSnapshot](../../netmon/app/lib/netmon/reconcile_snapshot.rb#L218), the alternate snapshot path. Agent rescoring also skips ordinary destroy updates once a score is present.

Impact: agent-only operation can show scored connections while anomaly and incident views remain empty or incomplete. Behavior that becomes apparent only after a flow accumulates traffic may not be rescored at termination.

Plan: extract shared detection, suppression, hit, and incident logic used by both ingestion paths. Re-evaluate at appropriate lifecycle points and/or periodically for active traffic, while retaining cooldowns and deduplication. Make heartbeat status distinguish transport health from successful flow/DNS processing; the [current health indicator](../../netmon/app/lib/netmon/metrics.rb#L18) only checks heartbeat arrival globally.

Acceptance: the same fixture produces equivalent expected detections through snapshot and agent ingestion. A high-volume completed flow produces the expected alertable hit/incident. One healthy router cannot hide another router's stalled collector.

### R3 — High monitoring risk: DNS log rotation can stop collection

Evidence: [Tail](../../netmon_agent/internal/dns/dnsmasq_tail.go#L57) checks `file.Stat()` on the already-open descriptor against its original inode. Renaming that file does not change its inode, so a replacement at the configured path is not detected. Copy-truncation is not handled. `ReadString` fragments received with EOF are discarded; reopening always seeks to the end.

Plan: compare the configured path's file identity with the open descriptor, detect truncation, retain incomplete lines, and define startup/reopen offset behavior. Bound line lengths and expose read errors, rotation events, and last successful DNS processing. Bound pending queries and expire inactive client entries in the correlator, whose client cache currently has no eviction.

Acceptance: Linux integration tests cover rename-and-create rotation, copytruncate, partial writes, missing/recreated files, oversized lines, and shutdown. Queries continue to appear after each rotation without unintended gaps or duplicates.

### R4 — Medium now; high for multiple routers: identity and flow accounting are underspecified

Evidence: [flow lookup](../../netmon/app/lib/netmon/agent_ingest.rb#L45) and the [unique connection index](../../netmon/db/schema.rb#L87) use only the five-tuple. Devices are identified by IP alone. Although ingestion receives `router_id`, these normalized keys and DNS correlation queries do not use it. The [agent](../../netmon_agent/internal/conntrack/conntrack.go#L64) labels every collected flow `OUT`; configured LAN interfaces/subnets and `emit_conntrack_new` have no consumers outside config declaration. [First-observation deltas](../../netmon/app/lib/netmon/agent_ingest.rb#L206) are zero, including a destroy-only observation, and connection counts increase for every event.

Impact: overlapping subnets on different routers merge devices and flows; inbound flows can be classified as outbound; missing NEW events undercount traffic; NEW/DESTROY updates count as separate connections. Reused tuples can inherit stale first-seen and DNS state. DNS correlation also lacks an upper time bound, allowing future observations relative to a replayed flow.

Plan: define router/network scope, a flow-lifetime identity, event ordering, counter-reset handling, and the meaning of connection counts. If only one router is supported initially, enforce that limitation. Implement source subnet/direction filtering and either honor or remove unused options. Bound DNS association by router, client, observation time, and a defined expiry/fallback policy; reverse DNS is supporting metadata rather than proof of the application hostname.

Acceptance: fixtures cover two routers with overlapping addresses, inbound/outbound IPv4 and IPv6, NEW plus DESTROY, destroy-only, tuple reuse, duplicate/reordered events, and stale/future DNS. Counts and byte totals match the documented semantics.

### O1 — Medium: retention does not bound all high-volume telemetry

Evidence: [cleanup](../../netmon/lib/tasks/netmon.rake#L24) removes selected rollups, anomalies, and incidents, but not `netmon_events` or stale connections. [DNS pruning](../../netmon/app/lib/netmon/dns/prune.rb#L12) is separate, and [recurring.yml](../../netmon/config/recurring.yml#L10) schedules only Solid Queue housekeeping. No supplied scheduler runs telemetry retention.

Plan: schedule bounded, indexed cleanup for raw events, DNS data, stale flows, metrics, and related records; document retention for identifying DNS and network activity. Prune DNS parents/children consistently, handle foreign-key relationships, monitor disk headroom, and test SQLite-aware backups and restoration. Budget time for database maintenance after deletes. Avoid logging entire batches; redact sensitive telemetry where practical.

Acceptance: expired records are removed in bounded batches without orphan records or prolonged write locks; fresh records remain. Disk/quota alerts fire, cleanup failures are visible, and a backup restores to a usable application.

### O2 — Medium: deployment and build configuration need consolidation

Evidence: the [recommended agent service](../../netmon_agent/deploy/systemd/netmon-agent.service#L7) runs as root without hardening; the [root-level alternative](../../netmon_agent.service#L20) has different paths and partial hardening. The [installer](../../netmon_agent_installer.sh#L23) resolves its repository root to the parent of its actual root-level location and expects absent example/config paths. Its build fallback uses predictable `/tmp/netmon-agent` as root. The [Docker build](../../netmon/Dockerfile#L37) uses Node 18 and downloads a moving `node-build` master archive to execute during the build. Node 18 is [end of life](https://nodejs.org/en/about/eol).

Plan: provide one supported installer/config/unit layout; use a private `mktemp` directory with cleanup for privileged builds. Prefer verifiable release artifacts, checksums, and reproducible builds. Constrain agent capabilities after testing netlink requirements, use read-only system/config access and narrowly writable state paths, and retain loopback metrics by default. Add metrics HTTP timeouts and a controlled shutdown that stops producers before closing channels, drains queues, and persists unsent data. Validate all numeric limits and durations. Update Node to a supported release and pin/verify build tooling. Configure production host allowlists and verify direct Rails access is restricted behind the intended TLS proxy.

Acceptance: install/upgrade works from a fresh checkout on supported Linux architectures; configuration is private, the agent can collect under the chosen capability restrictions, invalid settings fail clearly, and shutdown preserves queued work. Build inputs have documented versions and verification.

### O3 — High assurance gap: repository CI is misplaced and omits the actual test suite

Evidence: the Git repository root is `network_monitor`, but tracked workflow and Dependabot files live under [netmon/.github](../../.github/workflows/ci.yml#L1). GitHub requires workflows in the repository root's [`.github/workflows` directory](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax). The supplied test command runs Rails/Minitest while the meaningful suite is under `netmon/spec`; there are no Go jobs, dependency advisory audits, or DNS rotation/spool/client tests. Dependabot's configured `/` Bundler directory also does not match `netmon/` in this repository layout.

Plan: move GitHub configuration to the actual repository root and set Rails working directories explicitly. Run RSpec, Brakeman, a Ruby dependency advisory audit, JS dependency auditing, Go tests/race checks, `go vet`, and [govulncheck](https://go.dev/doc/security/vuln/) on Linux. Configure dependency updates for Bundler, JS, Go, and Actions with correct directories. Audit the locally replaced NFLOG module and record its upstream provenance; do not assume ordinary version scanning covers local changes. Build the production image and supported agent architectures in CI. Manage new audit dependencies explicitly when implementing this plan.

Acceptance: a pull request visibly runs each job, deliberately failing specs fail CI, and security failures have an owner and a time-bounded exception process. Record advisory results and actual reachable vulnerability findings before claiming dependencies are secure or vulnerable.

## Implementation sequence

Effort estimates are rough engineering days and include targeted tests; deployment constraints may change them. Execute as small reviewable changes, with database backups before identity/schema migrations.

| Phase | Work | Approximate effort | Completion gate |
| --- | --- | --- | --- |
| 1: Contain exposure | S1 operator access control, S2 safe rendering, S3 HTTPS/credential wiring, S5 authenticated probe actions; enable root CI/RSpec from O3 immediately | 3–6 days | Unauthorized access blocked; stored markup cannot execute; TLS and probe tests pass in CI |
| 2: Make ingestion trustworthy | S4 schema/limits and asynchronous enrichment; R1 event identity, atomicity, acknowledgements, spool recovery; O1 raw-event retention | 4–8 days | Mixed batches, retries, crashes, and replay have accurate durable outcomes; load and disk usage are bounded |
| 3: Restore monitoring guarantees | R2 detection parity; R3 DNS rotation; R4 direction, lifetime, accounting, and router scoping | 4–8 days | End-to-end fixtures produce expected traffic totals, domains, and incidents through both ingestion paths |
| 4: Operational hardening | Remaining O1/O2/O3 work: backups, supported builds, service restrictions, dependency audits, shutdown and observability | 3–6 days | Clean install, restore drill, production build, Linux/race tests, and advisory scans pass |

After correctness work, profile representative ingestion and dashboard load. Prioritize short transactions, batched writes, bounded initial dashboard queries, and independent enrichment workers. Keep SQLite while measured latency, lock waits, and retention capacity meet requirements; evaluate a separate ingestion process or PostgreSQL when those measurements justify the migration. Split the large inline dashboard script into tested modules as part of the rendering/CSP work.

## Verification performed and remaining limits

- Read controllers, models, queries, dashboard rendering, ingest/detection services, Go collection/transport/spool code, deployment files, and relevant existing tests; traced inputs to persistence, external processes, and browser sinks.
- Confirmed the nested GitHub configuration against the actual Git root. Checked tracked key/secret-related paths; `.kamal/secrets` uses references to environment/local key material rather than embedded raw credentials. This was not a complete history-wide secret scan.
- `bundle check` in `netmon/` failed because local dependencies cannot be satisfied and the lockfile lacks the Windows platform. RSpec and Brakeman were not run. Go, Node/npm, and govulncheck were not available on PATH. No dependency installation, lockfile changes, active network probing, or deployment was performed.
- No specific dependency CVE is asserted from version age alone. Node 18's unsupported status was verified against the official Node documentation. Current library advisories and Linux-only integration behavior remain implementation-phase validation work.
- Existing safeguards include fail-closed agent authentication when the server token is unset, CSRF protection on ordinary browser writes, parameterized query values and allowlisted sort directions in the reviewed queries, verified HTTPS when configured, 0600 spool files, a loopback metrics default, and a non-root Rails container. These reduce some risks but do not resolve the findings above.

For implementation guidance, the [Rails security guide](https://guides.rubyonrails.org/security.html) covers authentication, XSS, CSRF, host protection, and CSP. Findings in this document are based on this repository's code, not inferred from framework guidance.
