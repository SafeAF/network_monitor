package dns

import (
  "context"
  "crypto/sha256"
  "encoding/base64"
  "strings"
  "sync"
  "time"

  "netmon_agent/internal/config"
  "netmon_agent/internal/event"
  "netmon_agent/internal/metrics"
  "netmon_agent/internal/util"
)

type bucketKey struct {
  ClientIP string
  QType    string
  QNameHash string
  Bucket   time.Time
}

type cacheEntry struct {
  lastSeen time.Time
  qnames   *util.Ring[string]
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
  buckets := make(map[bucketKey]*event.DNSBucket)
  lastQueries := make(map[string]struct {
    key   bucketKey
    seen  time.Time
  })
  ticker := time.NewTicker(1 * time.Minute)
  defer ticker.Stop()

  for {
    select {
    case <-ctx.Done():
      return
    case line := <-lines:
      c.metrics.DNSLinesTotal.Inc()
      parsed, err := Parse(line, time.Now())
      if err != nil {
        c.metrics.DNSParseErrors.Inc()
        continue
      }
      if parsed.Action == "query" {
        c.trackClient(parsed.ClientIP, parsed.QName)
        bucketStart := parsed.TS.Truncate(time.Minute)
        qhash := c.hashQName(parsed.QName)
        key := bucketKey{ClientIP: parsed.ClientIP, QType: parsed.QType, QNameHash: qhash, Bucket: bucketStart}
        bucket := buckets[key]
        if bucket == nil {
          bucket = &event.DNSBucket{BucketStart: bucketStart, ClientIP: parsed.ClientIP, QType: parsed.QType, QNameHash: qhash}
          buckets[key] = bucket
        }
        bucket.Count++
        lastQueries[parsed.QName] = struct {
          key  bucketKey
          seen time.Time
        }{key: key, seen: parsed.TS}
      }
      if parsed.Action == "reply" && parsed.NXDomain {
        if entry, ok := lastQueries[parsed.QName]; ok {
          if parsed.TS.Sub(entry.seen) <= 2*time.Minute {
            if bucket, ok := buckets[entry.key]; ok {
              bucket.NXDomain++
            }
          }
        }
      }
    case <-ticker.C:
      now := time.Now().UTC()
      for _, bucket := range buckets {
        util.TrySend(out, c.metrics, "dns_bucket", event.Event{Type: "dns_bucket", TS: now, Data: *bucket})
        c.metrics.DNSBucketsEmitted.Inc()
      }
      buckets = make(map[bucketKey]*event.DNSBucket)
      c.emitHostIdentity(now, out)
      // prune lastQueries older than 5 minutes
      cutoff := now.Add(-5 * time.Minute)
      for q, entry := range lastQueries {
        if entry.seen.Before(cutoff) {
          delete(lastQueries, q)
        }
      }
    }
  }
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

func (c *Correlator) emitHostIdentity(now time.Time, out chan<- event.Event) {
  c.mu.RLock()
  defer c.mu.RUnlock()
  for ip, entry := range c.cache {
    if entry.lastSeen.IsZero() {
      continue
    }
    util.TrySend(out, c.metrics, "host_identity", event.Event{Type: "host_identity", TS: now, Data: event.HostIdentity{IP: ip, LastSeen: entry.lastSeen, RecentQNameHashes: entry.qnames.Values()}})
  }
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
