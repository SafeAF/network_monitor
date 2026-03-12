package httpclient

import (
  "bytes"
  "context"
  "encoding/json"
  "errors"
  "fmt"
  "io"
  "log"
  "math/rand"
  "net/http"
  "time"

  "netmon_agent/internal/event"
  "netmon_agent/internal/metrics"
  "netmon_agent/internal/spool"
)

func init() {
  rand.Seed(time.Now().UnixNano())
}

type Client struct {
  baseURL   string
  token     string
  batchMax  int
  batchWait time.Duration
  retryMax  int
  retryBase time.Duration
  flushWorkers int
  spoolReplayInterval time.Duration
  metrics   *metrics.Metrics
  spool     *spool.Spool
  httpClient *http.Client

  inCh chan event.Event
  priorityCh chan event.Event
}

func New(baseURL, token string, batchMax int, batchWait time.Duration, metrics *metrics.Metrics, spool *spool.Spool, queueDepth int, httpTimeout time.Duration, retryMax int, retryBase time.Duration, flushWorkers int, spoolReplayInterval time.Duration) *Client {
  if flushWorkers <= 0 {
    flushWorkers = 1
  }
  return &Client{
    baseURL: baseURL,
    token: token,
    batchMax: batchMax,
    batchWait: batchWait,
    retryMax: retryMax,
    retryBase: retryBase,
    flushWorkers: flushWorkers,
    spoolReplayInterval: spoolReplayInterval,
    metrics: metrics,
    spool: spool,
    httpClient: &http.Client{Timeout: httpTimeout},
    inCh: make(chan event.Event, queueDepth),
    priorityCh: make(chan event.Event, 32),
  }
}

func (c *Client) Ingest(event event.Event) bool {
  if c.metrics != nil {
    c.metrics.HTTPLastEnqueue.Set(float64(time.Now().Unix()))
  }
  select {
  case c.inCh <- event:
    return true
  default:
    c.metrics.DroppedLocalTotal.WithLabelValues("http_batch").Inc()
    return false
  }
}

func (c *Client) QueueDepth() int {
  return len(c.inCh)
}

func (c *Client) PriorityDepth() int {
  return len(c.priorityCh)
}

func (c *Client) Start(ctx context.Context, routerID string) {
  for i := 0; i < c.flushWorkers; i++ {
    go c.flushSupervisor(ctx, routerID)
  }
  go c.priorityLoop(ctx, routerID)
  go c.spoolReplayLoop(ctx)
}

func (c *Client) IngestPriority(event event.Event) bool {
  if c.metrics != nil {
    c.metrics.HTTPLastEnqueue.Set(float64(time.Now().Unix()))
  }
  select {
  case c.priorityCh <- event:
    return true
  default:
    c.metrics.DroppedLocalTotal.WithLabelValues("http_priority").Inc()
    return false
  }
}

func (c *Client) flushSupervisor(ctx context.Context, routerID string) {
  for {
    if ctx.Err() != nil {
      return
    }
    func() {
      defer func() {
        if r := recover(); r != nil {
          log.Printf("httpclient flushSupervisor panic: %v", r)
        }
      }()
      c.flushLoop(ctx, routerID)
    }()
    if ctx.Err() != nil {
      return
    }
    time.Sleep(1 * time.Second)
  }
}

func (c *Client) priorityLoop(ctx context.Context, routerID string) {
  for {
    select {
    case <-ctx.Done():
      return
    case ev := <-c.priorityCh:
      batch := []event.Event{ev}
      // Priority events (heartbeats) bypass flow backlog.
      _ = c.sendOrSpool(ctx, routerID, batch)
    }
  }
}

func (c *Client) flushLoop(ctx context.Context, routerID string) {
  wait := c.batchWait
  if wait <= 0 {
    wait = 1 * time.Second
  }
  ticker := time.NewTicker(wait)
  defer ticker.Stop()
  defer func() {
    if r := recover(); r != nil {
      log.Printf("httpclient flushLoop panic: %v", r)
    }
  }()

  batch := make([]event.Event, 0, c.batchMax)

  for {
    select {
    case <-ctx.Done():
      c.sendOrSpool(ctx, routerID, batch)
      return
    case ev := <-c.inCh:
      batch = append(batch, ev)
      if len(batch) >= c.batchMax {
        batch = c.sendOrSpool(ctx, routerID, batch)
      }
    case <-ticker.C:
      if len(batch) > 0 {
        batch = c.sendOrSpool(ctx, routerID, batch)
      }
    }
  }
}

func (c *Client) sendOrSpool(ctx context.Context, routerID string, batch []event.Event) []event.Event {
  if err := c.flushOnce(ctx, routerID, batch); err != nil {
    payload, _ := json.Marshal(event.Batch{RouterID: routerID, SentAt: time.Now().UTC(), Events: batch})
    if err := c.spool.Enqueue(payload); err != nil {
      c.metrics.SpoolDroppedTotal.Inc()
    }
  }
  return batch[:0]
}

func (c *Client) flushOnce(ctx context.Context, routerID string, batch []event.Event) error {
  if len(batch) == 0 {
    return nil
  }
  payload, err := json.Marshal(event.Batch{RouterID: routerID, SentAt: time.Now().UTC(), Events: batch})
  if err != nil {
    return err
  }
  // Keep live ingest non-blocking: on any transient error, spool and move on.
  return c.post(ctx, payload)
}

func (c *Client) postWithRetry(ctx context.Context, payload []byte) error {
  delays := backoffSchedule(c.retryBase, c.retryMax)
  var lastErr error
  for i := 0; i < len(delays); i++ {
    if i > 0 {
      select {
      case <-ctx.Done():
        return ctx.Err()
      case <-time.After(delays[i]):
      }
    }
    if err := c.post(ctx, payload); err == nil {
      return nil
    } else {
      lastErr = err
    }
  }
  return lastErr
}

func (c *Client) post(ctx context.Context, payload []byte) error {
  url := fmt.Sprintf("%s/api/v1/netmon/events/batch", c.baseURL)
  req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(payload))
  if err != nil {
    return err
  }
  req.Header.Set("Authorization", "Bearer "+c.token)
  req.Header.Set("Content-Type", "application/json")

  resp, err := c.httpClient.Do(req)
  if err != nil {
    c.metrics.HTTPSendErrors.WithLabelValues("net").Inc()
    if c.metrics != nil {
      c.metrics.HTTPLastSendError.Set(float64(time.Now().Unix()))
    }
    return err
  }
  defer resp.Body.Close()
  _, _ = io.Copy(io.Discard, resp.Body)
  if resp.StatusCode < 200 || resp.StatusCode >= 300 {
    c.metrics.HTTPSendErrors.WithLabelValues(fmt.Sprintf("%d", resp.StatusCode)).Inc()
    if c.metrics != nil {
      c.metrics.HTTPLastSendError.Set(float64(time.Now().Unix()))
    }
    return errors.New("http error")
  }
  c.metrics.HTTPBatchesSent.Inc()
  if c.metrics != nil {
    c.metrics.HTTPLastSendSuccess.Set(float64(time.Now().Unix()))
  }
  return nil
}

func (c *Client) replaySpool(ctx context.Context, routerID string) {
  // Prefer live traffic: only replay when live queue is mostly empty.
  if len(c.inCh) > c.batchMax {
    return
  }
  replayed := 0
  maxPerTick := 10
  for {
    if replayed >= maxPerTick {
      return
    }
    path, payload, err := c.spool.DequeueOldest()
    if err != nil {
      return
    }
    if err := c.postWithRetry(ctx, payload); err != nil {
      return
    }
    _ = c.spool.Ack(path)
    replayed++
  }
}

func (c *Client) spoolReplayLoop(ctx context.Context) {
  interval := c.spoolReplayInterval
  if interval <= 0 {
    interval = 5 * time.Second
  }
  ticker := time.NewTicker(interval)
  defer ticker.Stop()

  for {
    select {
    case <-ctx.Done():
      return
    case <-ticker.C:
      c.replaySpool(ctx, "")
    }
  }
}

func backoffSchedule(base time.Duration, max int) []time.Duration {
  if max <= 0 {
    max = 1
  }
  out := make([]time.Duration, 0, max)
  for i := 0; i < max; i++ {
    d := base * time.Duration(1<<i)
    out = append(out, jitter(d))
  }
  return out
}

func jitter(d time.Duration) time.Duration {
  if d <= 0 {
    return 0
  }
  // +/- 30% jitter
  delta := int64(float64(d) * 0.3)
  if delta == 0 {
    return d
  }
  n := rand.Int63n(delta*2) - delta
  return time.Duration(int64(d) + n)
}
