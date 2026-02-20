package httpclient

import (
  "bytes"
  "context"
  "encoding/json"
  "errors"
  "fmt"
  "io"
  "net/http"
  "time"

  "netmon_agent/internal/event"
  "netmon_agent/internal/metrics"
  "netmon_agent/internal/spool"
)

type Client struct {
  baseURL   string
  token     string
  batchMax  int
  batchWait time.Duration
  metrics   *metrics.Metrics
  spool     *spool.Spool

  inCh chan event.Event
}

func New(baseURL, token string, batchMax int, batchWait time.Duration, metrics *metrics.Metrics, spool *spool.Spool, queueDepth int) *Client {
  return &Client{
    baseURL: baseURL,
    token: token,
    batchMax: batchMax,
    batchWait: batchWait,
    metrics: metrics,
    spool: spool,
    inCh: make(chan event.Event, queueDepth),
  }
}

func (c *Client) Ingest(event event.Event) bool {
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

func (c *Client) Start(ctx context.Context, routerID string) {
  go c.flushLoop(ctx, routerID)
}

func (c *Client) flushLoop(ctx context.Context, routerID string) {
  ticker := time.NewTicker(c.batchWait)
  defer ticker.Stop()

  batch := make([]event.Event, 0, c.batchMax)

  for {
    select {
    case <-ctx.Done():
      _ = c.flush(ctx, routerID, batch)
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
      c.replaySpool(ctx, routerID)
    }
  }
}

func (c *Client) sendOrSpool(ctx context.Context, routerID string, batch []event.Event) []event.Event {
  if err := c.flush(ctx, routerID, batch); err != nil {
    payload, _ := json.Marshal(event.Batch{RouterID: routerID, SentAt: time.Now().UTC(), Events: batch})
    if err := c.spool.Enqueue(payload); err != nil {
      c.metrics.SpoolDroppedTotal.Inc()
    }
  }
  return batch[:0]
}

func (c *Client) flush(ctx context.Context, routerID string, batch []event.Event) error {
  if len(batch) == 0 {
    return nil
  }
  payload, err := json.Marshal(event.Batch{RouterID: routerID, SentAt: time.Now().UTC(), Events: batch})
  if err != nil {
    return err
  }
  return c.postWithRetry(ctx, payload)
}

func (c *Client) postWithRetry(ctx context.Context, payload []byte) error {
  delays := []time.Duration{1 * time.Second, 2 * time.Second, 4 * time.Second}
  var lastErr error
  for i := 0; i < len(delays)+1; i++ {
    if i > 0 {
      select {
      case <-ctx.Done():
        return ctx.Err()
      case <-time.After(delays[i-1]):
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

  resp, err := http.DefaultClient.Do(req)
  if err != nil {
    c.metrics.HTTPSendErrors.WithLabelValues("net").Inc()
    return err
  }
  defer resp.Body.Close()
  _, _ = io.Copy(io.Discard, resp.Body)
  if resp.StatusCode < 200 || resp.StatusCode >= 300 {
    c.metrics.HTTPSendErrors.WithLabelValues(fmt.Sprintf("%d", resp.StatusCode)).Inc()
    return errors.New("http error")
  }
  c.metrics.HTTPBatchesSent.Inc()
  return nil
}

func (c *Client) replaySpool(ctx context.Context, routerID string) {
  for {
    path, payload, err := c.spool.DequeueOldest()
    if err != nil {
      return
    }
    if err := c.post(ctx, payload); err != nil {
      return
    }
    _ = c.spool.Ack(path)
  }
}
