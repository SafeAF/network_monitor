package dns

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"net"
	"strconv"
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
	clientIP      string
	qname         string
	qtype         string
	resolver      string
	rcode         string
	answers       []event.DNSAnswer
	aliases       map[string]struct{}
	awaitingAlias bool
	ts            time.Time
	lastUpdate    time.Time
	responded     bool
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
	aliases := make(map[string][]*pendingQuery)
	ticker := time.NewTicker(pendingFlushInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			c.flushReady(time.Now().UTC().Add(pendingFlushInterval), pending, aliases, out)
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
				pq := &pendingQuery{
					clientIP:   parsed.ClientIP,
					qname:      parsed.QName,
					qtype:      strings.ToUpper(parsed.QType),
					ts:         parsed.TS.UTC(),
					lastUpdate: parsed.TS.UTC(),
					rcode:      "NOERROR",
					aliases:    make(map[string]struct{}),
				}
				pending[key] = append(pending[key], pq)
				if strings.EqualFold(parsed.QType, "PTR") {
					c.registerAlias(aliases, normalizePTRTarget(parsed.QName), pq)
				}
			case "forwarded":
				if pq := c.lookupPending(pending, aliases, key, parsed.TS, ""); pq != nil {
					pq.resolver = parsed.Resolver
					pq.lastUpdate = parsed.TS.UTC()
				}
			case "reply", "cached":
				answerType := answerTypeForRaw(parsed.Answer)
				if pq := c.lookupPending(pending, aliases, key, parsed.TS, answerType); pq != nil {
					pq.responded = true
					pq.lastUpdate = parsed.TS.UTC()
					if parsed.NXDomain {
						pq.rcode = "NXDOMAIN"
						pq.answers = nil
						pq.awaitingAlias = false
					} else if nodataMarker(parsed.Answer) {
						pq.rcode = "NOERROR"
						pq.awaitingAlias = false
					} else if answer := normalizePTRAnswer(pq.qtype, parsed.QName, parsed.Answer); answer != nil {
						pq.rcode = "NOERROR"
						pq.qname = answer.Name
						pq.answers = appendUniqueAnswer(pq.answers, *answer)
						pq.awaitingAlias = false
					} else {
						pq.rcode = "NOERROR"
						if answer := normalizeAnswer(parsed.QName, parsed.Answer); answer != nil {
							pq.answers = appendUniqueAnswer(pq.answers, *answer)
							pq.awaitingAlias = false
						} else if aliasKey := normalizeAlias(parsed.Answer); aliasKey != "" {
							c.registerAlias(aliases, aliasKey, pq)
							pq.awaitingAlias = true
						} else if cnameMarker(parsed.Answer) {
							pq.awaitingAlias = true
						}
					}
				}
			}
		case <-ticker.C:
			c.flushReady(time.Now().UTC(), pending, aliases, out)
			c.pruneExpired(time.Now().UTC(), pending, aliases)
		}
	}
}

func (c *Correlator) lookupPending(pending map[string][]*pendingQuery, aliases map[string][]*pendingQuery, key string, ts time.Time, answerType string) *pendingQuery {
	queries := pending[key]
	if len(queries) == 0 {
		queries = aliases[key]
	}
	if len(queries) == 0 {
		if fallback := c.lookupAwaitingAlias(pending, ts, answerType); fallback != nil {
			c.registerAlias(aliases, key, fallback)
			return fallback
		}
	}
	if len(queries) == 0 {
		return nil
	}

	live := make([]*pendingQuery, 0, len(queries))
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
		delete(aliases, key)
		return nil
	}
	if matched != nil {
		return matched
	}
	return live[len(live)-1]
}

func (c *Correlator) lookupAwaitingAlias(pending map[string][]*pendingQuery, ts time.Time, answerType string) *pendingQuery {
	var matched *pendingQuery
	for _, queries := range pending {
		for _, pq := range queries {
			if !pq.awaitingAlias {
				continue
			}
			if ts.UTC().Sub(pq.ts) > pendingQueryTTL {
				continue
			}
			if answerType != "" && pq.qtype != answerType {
				continue
			}
			if matched == nil || pq.lastUpdate.After(matched.lastUpdate) {
				matched = pq
			}
		}
	}
	return matched
}

func (c *Correlator) flushReady(now time.Time, pending map[string][]*pendingQuery, aliases map[string][]*pendingQuery, out chan<- event.Event) {
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
			c.unregisterAliases(aliases, pq)
		}
		if len(remaining) == 0 {
			delete(pending, key)
			continue
		}
		pending[key] = remaining
	}
}

func (c *Correlator) pruneExpired(now time.Time, pending map[string][]*pendingQuery, aliases map[string][]*pendingQuery) {
	cutoff := now.Add(-pendingQueryMaxAge)
	for key, queries := range pending {
		remaining := queries[:0]
		for _, pq := range queries {
			if pq.lastUpdate.Before(cutoff) {
				c.unregisterAliases(aliases, pq)
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

func normalizePTRAnswer(qtype, qname, raw string) *event.DNSAnswer {
	if !strings.EqualFold(qtype, "PTR") {
		return nil
	}

	targetIP := normalizePTRTarget(qname)
	if targetIP == "" {
		return nil
	}

	answerType := answerTypeForRaw(targetIP)
	if answerType == "" {
		return nil
	}

	name := normalizeHostname(raw)
	if name == "" {
		return nil
	}

	return &event.DNSAnswer{
		Name: name,
		Type: answerType,
		Data: targetIP,
	}
}

func normalizeAlias(raw string) string {
	value := strings.ToLower(strings.TrimSpace(strings.TrimSuffix(raw, ".")))
	if value == "" || net.ParseIP(value) != nil || cnameMarker(value) || nodataMarker(value) {
		return ""
	}
	return value
}

func cnameMarker(raw string) bool {
	return strings.EqualFold(strings.TrimSpace(raw), "<CNAME>")
}

func nodataMarker(raw string) bool {
	value := strings.ToUpper(strings.TrimSpace(raw))
	return value == "NODATA" || value == "NODATA-IPV6"
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

func (c *Correlator) registerAlias(aliases map[string][]*pendingQuery, alias string, pq *pendingQuery) {
	if alias == "" {
		return
	}
	if _, exists := pq.aliases[alias]; exists {
		return
	}
	pq.aliases[alias] = struct{}{}
	aliases[alias] = appendUniquePendingQuery(aliases[alias], pq)
}

func (c *Correlator) unregisterAliases(aliases map[string][]*pendingQuery, pq *pendingQuery) {
	for alias := range pq.aliases {
		queries := aliases[alias]
		if len(queries) == 0 {
			delete(aliases, alias)
			continue
		}

		remaining := queries[:0]
		for _, candidate := range queries {
			if candidate != pq {
				remaining = append(remaining, candidate)
			}
		}

		if len(remaining) == 0 {
			delete(aliases, alias)
			continue
		}
		aliases[alias] = remaining
	}
}

func appendUniquePendingQuery(queries []*pendingQuery, candidate *pendingQuery) []*pendingQuery {
	for _, existing := range queries {
		if existing == candidate {
			return queries
		}
	}
	return append(queries, candidate)
}

func normalizePTRTarget(raw string) string {
	value := strings.TrimSpace(strings.TrimSuffix(raw, "."))
	if ip := net.ParseIP(value); ip != nil {
		return ip.String()
	}

	if ip := parseIPv4PTR(value); ip != "" {
		return ip
	}

	return parseIPv6PTR(value)
}

func parseIPv4PTR(value string) string {
	const suffix = ".in-addr.arpa"
	value = strings.ToLower(value)
	if !strings.HasSuffix(value, suffix) {
		return ""
	}

	labels := strings.Split(strings.TrimSuffix(value, suffix), ".")
	if len(labels) != 4 {
		return ""
	}

	octets := make([]string, 0, 4)
	for i := len(labels) - 1; i >= 0; i-- {
		octet, err := strconv.Atoi(labels[i])
		if err != nil || octet < 0 || octet > 255 {
			return ""
		}
		octets = append(octets, labels[i])
	}

	ip := net.ParseIP(strings.Join(octets, "."))
	if ip == nil || ip.To4() == nil {
		return ""
	}

	return ip.String()
}

func parseIPv6PTR(value string) string {
	const suffix = ".ip6.arpa"
	value = strings.ToLower(value)
	if !strings.HasSuffix(value, suffix) {
		return ""
	}

	labels := strings.Split(strings.TrimSuffix(value, suffix), ".")
	if len(labels) != 32 {
		return ""
	}

	nibbles := make([]byte, 0, 32)
	for i := len(labels) - 1; i >= 0; i-- {
		label := labels[i]
		if len(label) != 1 || strings.IndexByte("0123456789abcdef", label[0]) == -1 {
			return ""
		}
		nibbles = append(nibbles, label[0])
	}

	groups := make([]string, 0, 8)
	for i := 0; i < len(nibbles); i += 4 {
		groups = append(groups, string(nibbles[i:i+4]))
	}

	ip := net.ParseIP(strings.Join(groups, ":"))
	if ip == nil || ip.To4() != nil {
		return ""
	}

	return ip.String()
}

func normalizeHostname(raw string) string {
	return strings.TrimSpace(strings.TrimSuffix(raw, "."))
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
