# Current Performance And Debugging Notes

## Main Performance Lesson

In this product, page slowness is often caused by ingest pressure rather than by the page itself.

That happens because:

- UI requests and ingest requests can share one Puma process
- ingest is write-heavy and query-heavy
- SQLite magnifies contention and queueing

## Performance Hotspots To Watch

- `/api/v1/netmon/events/batch`
- anomaly scoring in `Netmon::AgentIngest`
- dashboard polling endpoints
- large search result sets
- remote host detail pages that fan out to multiple history tables

## Primary Debugging Tools

- browser network tab
- `curl` from localhost on the Rails host
- Rails request logs
- `ps`, `vmstat`, `uptime`
- SQLite or DB shell
- targeted `rg` into controller/model code

## Fast Diagnostic Questions

1. Is the page slow from `curl 127.0.0.1`?
2. Is the HTML itself large?
3. Is `Views:` high, `ActiveRecord:` high, or both low with high total time?
4. Is there a hot competing endpoint?
5. Is ingest backlog starving the UI?

## Current Incident Reference

See:

- `docs/debugging/netmon-performance-postmortem-2026-03-29.md`
- `docs/debugging/rails-slow-page-checklist.md`

## Known Architectural Risk

Running the live app in Rails `development` with SQLite is workable for small LAN deployments, but it is not a neutral configuration. It directly affects latency, especially under continuous ingest.
