# Current Operations

## Rails App Modes

### Local/dev-style LAN service

Common for router-adjacent or workstation deployments.

Characteristics:

- often runs on port `3000`
- may run in Rails `development`
- usually LAN-bound or LAN-exposed
- may use SQLite directly in `storage/`

### Containerized/deployed Rails app

The repo includes Kamal-oriented production config.

Characteristics:

- Rails `production`
- Puma with configured workers/threads
- Solid Cache / Solid Queue / Solid Cable databases
- persistent `storage/` volumes

## Important Rake Tasks

- `rake netmon:ingest_once`
- `rake netmon:ingest_loop`
- `rake netmon:recompute_baselines`
- `rake netmon:cleanup`
- `rake netmon:dns_prune`

## Environment Variables

Important Rails-side values:

- `NETMON_API_TOKEN`
- `RAILS_ENV`
- `RAILS_MAX_THREADS`
- `WEB_CONCURRENCY`
- `SOLID_QUEUE_IN_PUMA`

Useful optional debug flags in development:

- `RAILS_LOG_LEVEL`
- `RAILS_VERBOSE_QUERY_LOGS`
- `RAILS_VERBOSE_ENQUEUE_LOGS`
- `RAILS_VIEW_ANNOTATIONS`
- `RAILS_SERVER_TIMING`

## Database

Current default DBs are SQLite.

Files:

- development: `storage/development.sqlite3`
- test: `storage/test.sqlite3`
- production primary/cache/queue/cable under `storage/`

Operational implication:

- SQLite is simple but can become a performance bottleneck when ingest and UI share the same app server

## Deployment Files

- `netmon/config/deploy.yml`
- `netmon/config/puma.rb`
- `netmon/config/database.yml`

## Recommended Operational Pattern

For smaller LAN-only installs:

- run Rails with sane logging
- keep agent and Rails on separate hosts if possible
- avoid sharing one overloaded single-process app server between heavy ingest and interactive UI

For more durable installs:

- run Rails in production
- use proper process supervision
- consider a database backend better suited to sustained concurrent write/read load
