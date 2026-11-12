package dns

import (
	"context"
	"fmt"
	"testing"
	"time"

	"netmon_agent/internal/config"
	"netmon_agent/internal/event"
)

func TestCorrelatorStopsOnClosedInputAndBoundsPendingQueries(t *testing.T) {
	corr := NewCorrelator(&config.Config{QnameHashCap: 8}, nil)
	lines := make(chan string, maxPendingQueries+20)
	prefix := time.Now().Format("Jan 2 15:04:05")
	for i := 0; i < cap(lines); i++ {
		lines <- fmt.Sprintf("%s dnsmasq[1]: query[A] name%d.example from 10.0.0.20", prefix, i)
	}
	close(lines)
	corr.Start(context.Background(), lines, make(chan event.Event, 1))
	if corr.pendingCount != maxPendingQueries {
		t.Fatalf("unbounded pending queries: %d", corr.pendingCount)
	}
}

func TestClientContextsAreBoundedAndExpire(t *testing.T) {
	corr := NewCorrelator(&config.Config{QnameHashCap: 8}, nil)
	for i := 0; i < maxClientContexts+20; i++ {
		corr.trackClient(fmt.Sprintf("10.0.%d.%d", i/256, i%256), "example.com")
	}
	if len(corr.cache) != maxClientContexts {
		t.Fatal("client cache exceeded capacity")
	}
	for _, entry := range corr.cache {
		entry.lastSeen = time.Now().Add(-clientContextTTL - time.Second)
	}
	if corr.DNSContextForIP("10.0.0.1") != nil {
		t.Fatal("returned expired context")
	}
	corr.pruneClients(time.Now())
	if len(corr.cache) != 0 {
		t.Fatal("expired client contexts retained")
	}
	corr.trackClient("10.0.0.20", "fresh.example")
	if corr.DNSContextForIP("10.0.0.20") == nil {
		t.Fatal("cache did not admit clients after expiry")
	}
}

func TestOverflowedQueriesNeverEmitTruncatedAnswers(t *testing.T) {
	corr := NewCorrelator(&config.Config{QnameHashCap: 8}, nil)
	now := time.Now()
	pq := &pendingQuery{qname: "example.com", responded: true, lastUpdate: now.Add(-time.Second), aliases: make(map[string]struct{})}
	for i := 0; i <= maxQueryAnswers; i++ {
		corr.appendAnswer(pq, event.DNSAnswer{Type: "A", Data: fmt.Sprintf("203.0.113.%d", i)})
	}
	if len(pq.answers) != maxQueryAnswers || !pq.overflowed {
		t.Fatal("answer list was not bounded")
	}
	pending := map[string][]*pendingQuery{"example.com": {pq}}
	corr.pendingCount = 1
	out := make(chan event.Event, 1)
	corr.flushReady(now, pending, make(map[string][]*pendingQuery), out)
	if len(out) != 0 || corr.pendingCount != 0 {
		t.Fatal("emitted an incomplete response or retained query")
	}
}

func TestAliasCountIsBounded(t *testing.T) {
	corr := NewCorrelator(&config.Config{}, nil)
	pq := &pendingQuery{aliases: make(map[string]struct{})}
	aliases := make(map[string][]*pendingQuery)
	for i := 0; i <= maxQueryAliases; i++ {
		corr.registerAlias(aliases, fmt.Sprintf("alias%d.example", i), pq)
	}
	if len(aliases) != maxQueryAliases || !pq.overflowed {
		t.Fatal("alias memory was not bounded")
	}
	corr.unregisterAliases(aliases, pq)
	if len(aliases) != 0 {
		t.Fatal("retained query aliases after removal")
	}
}

func TestExpiredLookupDoesNotLeakPendingAccounting(t *testing.T) {
	corr := NewCorrelator(&config.Config{}, nil)
	now := time.Now()
	pq := &pendingQuery{ts: now.Add(-3 * time.Minute), lastUpdate: now.Add(-3 * time.Minute), aliases: make(map[string]struct{})}
	pending := map[string][]*pendingQuery{"old.example": {pq}}
	aliases := make(map[string][]*pendingQuery)
	corr.pendingCount = 1
	if corr.lookupPending(pending, aliases, "old.example", now, "A") != nil {
		t.Fatal("matched expired query")
	}
	corr.pruneExpired(now.Add(6*time.Minute), pending, aliases)
	if corr.pendingCount != 0 || len(pending) != 0 {
		t.Fatal("expired lookup leaked pending capacity")
	}
}

func TestPendingCompactionDoesNotRetainRemovedQueries(t *testing.T) {
	corr := NewCorrelator(&config.Config{}, nil)
	now := time.Now()
	queries := make([]*pendingQuery, 1000)
	aliases := make(map[string][]*pendingQuery)
	for i := range queries {
		pq := &pendingQuery{responded: i != 999, lastUpdate: now.Add(-time.Second), aliases: make(map[string]struct{})}
		queries[i] = pq
		corr.registerAlias(aliases, "shared.example", pq)
	}
	pending := map[string][]*pendingQuery{"example.com": queries}
	corr.pendingCount = len(queries)
	corr.flushReady(now, pending, aliases, make(chan event.Event, len(queries)))
	if corr.pendingCount != 1 || cap(pending["example.com"]) > 2 || cap(aliases["shared.example"]) > 2 {
		t.Fatal("removed queries retained oversized backing arrays")
	}
	for _, stale := range queries[1:] {
		if stale != nil {
			t.Fatal("removed query remains referenced")
		}
	}
}
