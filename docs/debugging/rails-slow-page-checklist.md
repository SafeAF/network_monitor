# Rails Slow Page Checklist

Use this when a Rails page feels slow and you need to determine where time is actually going.

## Request Path

For a single page load, think in this order:

1. Browser navigation starts.
2. Browser requests HTML.
3. Rails router dispatches to controller action.
4. Controller runs queries and builds objects.
5. View renders HTML.
6. Browser requests assets referenced by the HTML.
7. Browser executes JS, applies CSS, and paints.
8. Any follow-up XHR/fetch polling starts.

Latency can accumulate at every stage:

- client-side queueing
- DNS/TCP/TLS/network
- reverse proxy / app server queue
- controller code
- DB query execution
- N+1 query loops
- view rendering
- oversized HTML responses
- missing or slow assets
- client-side JS execution
- background/polling requests starving the server

## Metrics By Layer

### Browser / client

Questions:

- Is the browser waiting on the first byte, or downloading/rendering a large page?
- Is the delay on the main HTML request, assets, or follow-up XHR?

Measurements:

- browser network tab
- `DOMContentLoaded`
- `load`
- per-request `time_starttransfer`
- per-request size
- JS console errors

Signals:

- High `time_starttransfer` with small response body usually means server-side delay.
- Large download size with normal server timing points to response bloat or asset size.
- 404 or slow CSS/JS requests point to asset pipeline issues.
- Fast network but slow paint or scripting points to client-side work.

### App server

Questions:

- Is Puma/Passenger/Unicorn busy or saturated?
- Are requests queued behind long-running endpoints?

Measurements:

- `ps`
- CPU for app processes
- thread/worker count
- curl from localhost on the server
- app logs with request durations

Signals:

- A tiny HTML page that is slow from `curl localhost` is not a client/network issue.
- One hot Puma process at very high CPU with the box otherwise idle usually means app hot-path contention.
- Repeated background or polling endpoints can starve normal pages.

### Controller / view

Questions:

- Is the action itself slow?
- Is view rendering the expensive part?

Measurements:

- Rails log line: `Completed 200 OK in ... (Views: ... | ActiveRecord: ...)`
- rendering annotations if intentionally enabled
- response size

Signals:

- High `Views:` and low `ActiveRecord:` suggests rendering or serialization cost.
- Low `Views:` and low `ActiveRecord:` with high total time suggests queueing or lock contention.
- Small HTML body and long server response time suggests waiting on other server work.

### DB / query layer

Questions:

- Are queries individually slow?
- Is the action making too many queries?
- Is there lock contention?

Measurements:

- Rails query count from logs
- per-query timings in logs
- `EXPLAIN QUERY PLAN` / `EXPLAIN ANALYZE`
- table sizes
- backend type: SQLite/Postgres/etc.

Signals:

- Very high query count means N+1 or repeated per-row logic.
- A few giant queries suggest aggregation/index problems.
- SQLite on a live multi-request app often shows request queueing and lock sensitivity.

### Assets

Questions:

- Are CSS/JS assets missing, miscompiled, or too large?

Measurements:

- asset requests in browser network tab
- HTML source for linked assets
- asset response codes

Signals:

- HTML loads but CSS/JS 404s indicate wrong asset references.
- Preload warnings plus 404s often mean a layout/include bug.

## Fast Triage Flow

1. Reproduce with browser network tab open.
2. Reproduce with `curl` from the app server itself.
3. Check Rails request logs for the same timestamp.
4. Compare `total time`, `Views`, `ActiveRecord`, query count, and response size.
5. Look for one hot endpoint running repeatedly.
6. Inspect the action code that matches the slow log entry.
7. Fix the highest-leverage hot path first.
8. Re-measure from localhost, then browser.

## What Distinguishes Each Failure Mode

### DB slowness

- High `ActiveRecord:` time
- Slow individual SQL statements
- Many SQL statements
- `EXPLAIN` shows scans/sorts/grouping pain

### Render slowness

- High `Views:` time
- Large templates or large collections rendered in ERB
- HTML size unusually large

### Asset slowness

- Main HTML is fast but page still feels incomplete
- missing CSS/JS
- 404s or long asset downloads
- console/preload warnings

### Client slowness

- Server and asset requests are fast
- browser scripting/layout/paint is slow
- CPU spikes only in browser

### App server queueing

- Main HTML request has low `Views:` and low `ActiveRecord:`, but high total time
- localhost `curl` is still slow
- one or two endpoints dominate Puma threads/processes

## Investigation Template

For each step, record:

- Symptom:
- Suspected layer:
- Measurement taken:
- Result:
- Conclusion:
- Next action:

## Tools And What They Answer

### Browser network tab

- Which request is slow?
- Is the wait on HTML, assets, or XHR?
- Is first byte slow or download/render slow?

### `curl` from localhost on the app server

- Is the problem server-side or client/network-side?

### Rails logs

- Which controller/action is slow?
- Was it DB time, view time, or queueing?
- How many queries ran?

### `rg` / source inspection

- What code path corresponds to the slow action?
- Are there obvious loops, N+1s, or repeated expensive helpers?

### `ps`, `uptime`, `vmstat`, `free`

- Is the machine itself overloaded?
- Is one process hot while the rest of the box is idle?

### DB shell / `sqlite3` / `psql`

- How big are the tables?
- What backend is in use?
- Can the query plan explain the latency?

### Tests

- Did the hot-path optimization preserve behavior?
- Can the regression be locked in?

## Common Patterns

### Pattern: tiny page, huge wait

Usually means request starvation, not rendering.

### Pattern: high query count, modest per-query time

Usually repeated per-event or per-row application logic.

### Pattern: page slow only in browser

Usually assets or client-side JS.

### Pattern: page fast on localhost curl, slow from browser

Usually network, proxy, TLS, or client-side rendering.

## Short Postmortem Template

- Root cause:
- Why it caused slowness:
- Why the initial symptom was misleading:
- Fix:
- Validation:
- How to recognize this pattern next time:
