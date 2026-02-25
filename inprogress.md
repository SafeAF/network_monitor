it looks like incidents and anomalies arent being populated? 
integrate dns masq changes

no whois 

flags and state are no showing up
pagination on connections main page

graphs are resetting to 10 min still shows the selected timescale but reverts to 10min graph

pagination with first last next and numbered pages

when i click hide time wait it renders the connections but then i try to uncheck the box and click apply and its still doing the filtering it doesnt reset

show only open connections in table

go mod tidy
GOCACHE=/tmp/go-build GOOS=linux GOARCH=386 CGO_ENABLED=0 go build -o /tmp/netmon_agent_linux_386 ./cmd/netmon_agent

k that worked. im a bit concerned about keeping all these connections in the connections main table that are stale and past time_wait. those should go into search/connections but not be on the main page table if they are long since dead.

go agent collector is dying after a couple minutes of running

graceful kill of go agent, i have to kill -9 it right now

in search/connections show state and flags, let user adjust which fields are shown. add page links and last etc pagination

how to hide 10.0.0.1:53 and the like connections

ui jitters when changing columns on main connections table


NetmonEvent.order(created_at: :desc).limit(3).pluck(:event_type, :created_at)
# 1) Metrics snapshot
curl -s http://127.0.0.1:9109/metrics | rg "http_batches_sent_total|http_send_errors_total|spool_bytes|spool_batches|conntrack_destroy_total|nflog_events_total|dns_lines_total"

# 2) Agent stdout (if running in foreground) or last logs if you started it in a tmux/screen
rails c
NetmonEvent.order(created_at: :desc).limit(5).pluck(:event_type, :created_at)
date -u
curl -s http://127.0.0.1:9109/metrics | rg "http_batches_sent_total|http_send_errors_total|spool_bytes|spool_batches|conntrack_destroy_total|nflog_events_total|dns_lines_total"
