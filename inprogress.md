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