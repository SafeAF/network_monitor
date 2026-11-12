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
	baseURL             string
	token               string
	batchMax            int
	batchWait           time.Duration
	retryMax            int
	retryBase           time.Duration
	flushWorkers        int
	spoolReplayInterval time.Duration
	metrics             *metrics.Metrics
	spool               *spool.Spool
	httpClient          *http.Client

	inCh       chan event.Event
	priorityCh chan event.Event
}

func New(baseURL, token string, batchMax int, batchWait time.Duration, metrics *metrics.Metrics, spool *spool.Spool, queueDepth int, httpTimeout time.Duration, retryMax int, retryBase time.Duration, flushWorkers int, spoolReplayInterval time.Duration) *Client {
	if flushWorkers <= 0 {
		flushWorkers = 1
	}
	return &Client{
		baseURL:             baseURL,
		token:               token,
		batchMax:            batchMax,
		batchWait:           batchWait,
		retryMax:            retryMax,
		retryBase:           retryBase,
		flushWorkers:        flushWorkers,
		spoolReplayInterval: spoolReplayInterval,
		metrics:             metrics,
		spool:               spool,
		// Ingest has a fixed endpoint. Reject every redirect, including HTTPS to
		// HTTP, rather than resending a bearer token to a different destination.
		httpClient: &http.Client{Timeout: httpTimeout, CheckRedirect: func(req *http.Request, via []*http.Request) error {
			return http.ErrUseLastResponse
		}},
		inCh:       make(chan event.Event, queueDepth),
		priorityCh: make(chan event.Event, 32),
	}
}

func (c *Client) Ingest(event event.Event) bool {
	if err := event.EnsureID(); err != nil {
		log.Printf("event identity allocation failed: %v", err)
		return false
	}
	if c.metrics != nil {
		c.metrics.HTTPLastEnqueue.Set(float64(time.Now().Unix()))
	}
	select {
	case c.inCh <- event:
		return true
	default:
		if c.metrics != nil {
			c.metrics.DroppedLocalTotal.WithLabelValues("http_batch").Inc()
		}
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
	if err := event.EnsureID(); err != nil {
		log.Printf("event identity allocation failed: %v", err)
		return false
	}
	if c.metrics != nil {
		c.metrics.HTTPLastEnqueue.Set(float64(time.Now().Unix()))
	}
	select {
	case c.priorityCh <- event:
		return true
	default:
		if c.metrics != nil {
			c.metrics.DroppedLocalTotal.WithLabelValues("http_priority").Inc()
		}
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
	if len(batch) == 0 {
		return batch[:0]
	}
	payload, err := json.Marshal(event.Batch{RouterID: routerID, SentAt: time.Now().UTC(), Events: batch})
	if err != nil {
		log.Printf("event batch encoding failed: %v", err)
		return batch[:0]
	}
	if len(payload) > 4*1024*1024 && len(batch) > 1 {
		middle := len(batch) / 2
		c.sendOrSpool(ctx, routerID, batch[:middle])
		c.sendOrSpool(ctx, routerID, batch[middle:])
		return batch[:0]
	}
	if err := c.post(ctx, payload); err != nil {
		var rejected *permanentRejection
		if errors.As(err, &rejected) {
			if c.quarantine(payload, rejected.reason, rejected.acknowledgement) == nil {
				return batch[:0]
			}
		}
		if err := c.spool.Enqueue(payload); err != nil {
			log.Printf("spool enqueue failed: %v", err)
			if c.metrics != nil {
				c.metrics.SpoolDroppedTotal.Inc()
			}
		}
	}
	return batch[:0]
}

func (c *Client) quarantine(payload []byte, reason string, acknowledgement ...json.RawMessage) error {
	err := c.spool.Quarantine(payload, reason, acknowledgement...)
	if err != nil {
		log.Printf("spool quarantine failed reason=%s error=%v", reason, err)
	} else {
		log.Printf("spool batch quarantined reason=%s", reason)
	}
	return err
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
			var rejected *permanentRejection
			if errors.As(err, &rejected) {
				return err
			}
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
	req.Header.Set("X-Netmon-Protocol-Version", "1")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		if c.metrics != nil {
			c.metrics.HTTPSendErrors.WithLabelValues("net").Inc()
			c.metrics.HTTPLastSendError.Set(float64(time.Now().Unix()))
		}
		return err
	}
	defer resp.Body.Close()
	body, readErr := io.ReadAll(io.LimitReader(resp.Body, 512*1024+1))
	if readErr != nil || len(body) > 512*1024 {
		return errors.New("unreadable or oversized acknowledgement")
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		if c.metrics != nil {
			c.metrics.HTTPSendErrors.WithLabelValues(fmt.Sprintf("%d", resp.StatusCode)).Inc()
			c.metrics.HTTPLastSendError.Set(float64(time.Now().Unix()))
		}
		return permanentHTTPRejection(resp.StatusCode, body)
	}
	if err := checkAcknowledgement(payload, body); err != nil {
		if c.metrics != nil {
			c.metrics.HTTPSendErrors.WithLabelValues("acknowledgement").Inc()
			c.metrics.HTTPLastSendError.Set(float64(time.Now().Unix()))
		}
		return err
	}
	if c.metrics != nil {
		c.metrics.HTTPBatchesSent.Inc()
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
			if path != "" {
				log.Printf("spool read failed; original retained: %v", err)
			}
			return
		}
		if len(payload) > 4*1024*1024 || !json.Valid(payload) {
			if c.quarantine(payload, "corrupt_spool") != nil {
				return
			}
			if err := c.spool.Ack(path); err != nil {
				log.Printf("spool acknowledgement failed: %v", err)
				return
			}
			replayed++
			continue
		}
		if err := c.postWithRetry(ctx, payload); err != nil {
			var rejected *permanentRejection
			if !errors.As(err, &rejected) || c.quarantine(payload, rejected.reason, rejected.acknowledgement) != nil {
				return
			}
		}
		if err := c.spool.Ack(path); err != nil {
			log.Printf("spool acknowledgement failed: %v", err)
			return
		}
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
