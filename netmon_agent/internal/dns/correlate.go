package dns

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"net"
	"strings"
	"sync"
	"time"

	"netmon_agent/internal/config"
	"netmon_agent/internal/event"
	"netmon_agent/internal/metrics"
	"netmon_agent/internal/util"
)

const (
	pendingQueryTTL      = 2 * time.Minute
	pendingQueryMaxAge   = 5 * time.Minute
	pendingFlushInterval = 500 * time.Millisecond
)

type cacheEntry struct {
	lastSeen time.Time
	qnames   *util.Ring[string]
}

type pendingQuery struct {
	clientIP   string
	qname      string
	qtype      string
	resolver   string
	rcode      string
	answers    []event.DNSAnswer
	ts         time.Time
	lastUpdate time.Time
	responded  bool
}

type Correlator struct {
	cfg     *config.Config
	metrics *metrics.Metrics
	mu      sync.RWMutex
	cache   map[string]*cacheEntry
}

func NewCorrelator(cfg *config.Config, metrics *metrics.Metrics) *Correlator {
	return &Correlator{cfg: cfg, metrics: metrics, cache: make(map[string]*cacheEntry)}
}

func (c *Correlator) Start(ctx context.Context, lines <-chan string, out chan<- event.Event) {
	pending := make(map[string][]*pendingQuery)
	ticker := time.NewTicker(pendingFlushInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			c.flushReady(time.Now().UTC().Add(pendingFlushInterval), pending, out)
			return
		case line := <-lines:
			c.incDNSLines()

			parsed, err := Parse(line, time.Now())
			if err != nil {
				c.incDNSParseErrors()
				continue
			}

			key := strings.ToLower(parsed.QName)
			switch parsed.Action {
			case "query":
				c.trackClient(parsed.ClientIP, parsed.QName)
				pending[key] = append(pending[key], &pendingQuery{
					clientIP:   parsed.ClientIP,
					qname:      parsed.QName,
					qtype:      strings.ToUpper(parsed.QType),
					ts:         parsed.TS.UTC(),
					lastUpdate: parsed.TS.UTC(),
					rcode:      "NOERROR",
				})
			case "forwarded":
				if pq := c.lookupPending(pending, key, parsed.TS, ""); pq != nil {
					pq.resolver = parsed.Resolver
					pq.lastUpdate = parsed.TS.UTC()
				}
			case "reply", "cached":
				answerType := answerTypeForRaw(parsed.Answer)
				if pq := c.lookupPending(pending, key, parsed.TS, answerType); pq != nil {
					pq.responded = true
					pq.lastUpdate = parsed.TS.UTC()
					if parsed.NXDomain {
						pq.rcode = "NXDOMAIN"
						pq.answers = nil
					} else {
						pq.rcode = "NOERROR"
						if answer := normalizeAnswer(parsed.QName, parsed.Answer); answer != nil {
							pq.answers = appendUniqueAnswer(pq.answers, *answer)
						}
					}
				}
			}
		case <-ticker.C:
			c.flushReady(time.Now().UTC(), pending, out)
			c.pruneExpired(time.Now().UTC(), pending)
		}
	}
}

func (c *Correlator) lookupPending(pending map[string][]*pendingQuery, key string, ts time.Time, answerType string) *pendingQuery {
	queries := pending[key]
	if len(queries) == 0 {
		return nil
	}

	live := queries[:0]
	var matched *pendingQuery
	for _, pq := range queries {
		if ts.UTC().Sub(pq.ts) > pendingQueryTTL {
			continue
		}
		live = append(live, pq)
		if answerType == "" || pq.qtype == answerType {
			matched = pq
		}
	}
	if len(live) == 0 {
		delete(pending, key)
		return nil
	}
	pending[key] = live
	if matched != nil {
		return matched
	}
	return live[len(live)-1]
}

func (c *Correlator) flushReady(now time.Time, pending map[string][]*pendingQuery, out chan<- event.Event) {
	for key, queries := range pending {
		remaining := queries[:0]
		for _, pq := range queries {
			if !pq.responded || now.Sub(pq.lastUpdate) < pendingFlushInterval {
				remaining = append(remaining, pq)
				continue
			}

			util.TrySend(out, c.metrics, "dns_response", event.Event{
				Type: "dns_response",
				TS:   pq.lastUpdate,
				Data: event.DNSResponse{
					ClientIP: pq.clientIP,
					QName:    pq.qname,
					QType:    pq.qtype,
					RCode:    pq.rcode,
					Resolver: pq.resolver,
					Answers:  append([]event.DNSAnswer{}, pq.answers...),
				},
			})

			c.incDNSResponsesEmitted()
		}
		if len(remaining) == 0 {
			delete(pending, key)
			continue
		}
		pending[key] = remaining
	}
}

func (c *Correlator) pruneExpired(now time.Time, pending map[string][]*pendingQuery) {
	cutoff := now.Add(-pendingQueryMaxAge)
	for key, queries := range pending {
		remaining := queries[:0]
		for _, pq := range queries {
			if pq.lastUpdate.Before(cutoff) {
				continue
			}
			remaining = append(remaining, pq)
		}
		if len(remaining) == 0 {
			delete(pending, key)
			continue
		}
		pending[key] = remaining
	}
}

func normalizeAnswer(qname, raw string) *event.DNSAnswer {
	ip := net.ParseIP(strings.TrimSpace(raw))
	if ip == nil {
		return nil
	}

	answerType := answerTypeForIP(ip)
	if answerType == "" {
		return nil
	}

	return &event.DNSAnswer{
		Name: qname,
		Type: answerType,
		Data: ip.String(),
	}
}

func answerTypeForRaw(raw string) string {
	ip := net.ParseIP(strings.TrimSpace(raw))
	return answerTypeForIP(ip)
}

func answerTypeForIP(ip net.IP) string {
	if ip == nil {
		return ""
	}

	answerType := "A"
	if ip.To4() == nil {
		answerType = "AAAA"
	}
	return answerType
}

func appendUniqueAnswer(answers []event.DNSAnswer, answer event.DNSAnswer) []event.DNSAnswer {
	for _, existing := range answers {
		if existing.Type == answer.Type && existing.Data == answer.Data {
			return answers
		}
	}
	return append(answers, answer)
}

func (c *Correlator) trackClient(clientIP, qname string) {
	if clientIP == "" {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	entry := c.cache[clientIP]
	if entry == nil {
		entry = &cacheEntry{qnames: util.NewRing[string](c.cfg.QnameHashCap)}
		c.cache[clientIP] = entry
	}
	entry.lastSeen = time.Now().UTC()
	entry.qnames.Add(c.hashQName(qname))
}

func (c *Correlator) hashQName(qname string) string {
	q := strings.ToLower(strings.TrimSpace(qname))
	sum := sha256.Sum256([]byte(c.cfg.QnameHashSalt + q))
	return "b64:" + base64.StdEncoding.EncodeToString(sum[:])
}

func (c *Correlator) DNSContextForIP(ip string) *event.DNSContext {
	c.mu.RLock()
	defer c.mu.RUnlock()
	entry := c.cache[ip]
	if entry == nil {
		return nil
	}
	return &event.DNSContext{RecentQNameHashes: entry.qnames.Values(), LastSeen: entry.lastSeen.Format(time.RFC3339)}
}

func (c *Correlator) incDNSLines() {
	if c.metrics != nil {
		c.metrics.DNSLinesTotal.Inc()
	}
}

func (c *Correlator) incDNSParseErrors() {
	if c.metrics != nil {
		c.metrics.DNSParseErrors.Inc()
	}
}

func (c *Correlator) incDNSResponsesEmitted() {
	if c.metrics != nil {
		c.metrics.DNSBucketsEmitted.Inc()
	}
}
