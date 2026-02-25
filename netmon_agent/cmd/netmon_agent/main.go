package main

import (
  "context"
  "flag"
  "log"
  "net/http"
  "os"
  "os/signal"
  "syscall"
  "time"

  "github.com/prometheus/client_golang/prometheus/promhttp"

  "netmon_agent/internal/config"
  "netmon_agent/internal/conntrack"
  "netmon_agent/internal/dns"
  "netmon_agent/internal/event"
  "netmon_agent/internal/httpclient"
  "netmon_agent/internal/metrics"
  "netmon_agent/internal/nflog"
  "netmon_agent/internal/spool"
)

func main() {
  var cfgPath string
  flag.StringVar(&cfgPath, "config", "/etc/netmon-agent/config.yaml", "config path")
  flag.Parse()

  cfg, err := config.Load(cfgPath)
  if err != nil {
    log.Fatalf("config load failed: %v", err)
  }

  ctx, cancel := context.WithCancel(context.Background())
  defer cancel()

  sigCh := make(chan os.Signal, 2)
  signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
  go func() {
    <-sigCh
    cancel()
  }()

  m := metrics.New()

  sp := spool.New(cfg.SpoolDir, cfg.SpoolMaxBytes)
  if err := sp.Ensure(); err != nil {
    log.Fatalf("spool init failed: %v", err)
  }

  httpClient := httpclient.New(
    cfg.RailsBaseURL,
    cfg.AuthToken,
    cfg.BatchMaxEvents,
    cfg.BatchMaxWait,
    m,
    sp,
    cfg.QueueDepth,
    cfg.HttpTimeout,
    cfg.HttpRetryMax,
    cfg.HttpRetryBase,
    cfg.SpoolReplayInterval,
  )
  httpClient.Start(ctx, cfg.RouterID)

  // Metrics endpoint
  go func() {
    mux := http.NewServeMux()
    mux.Handle("/metrics", promhttp.Handler())
    srv := &http.Server{Addr: cfg.MetricsBind, Handler: mux}
    if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
      log.Printf("metrics server error: %v", err)
    }
  }()

  // Event fanout
  eventCh := make(chan event.Event, cfg.QueueDepth)
  go func() {
    for ev := range eventCh {
      httpClient.Ingest(ev)
    }
  }()

  // Heartbeat
  go func() {
    ticker := time.NewTicker(cfg.HeartbeatInterval)
    defer ticker.Stop()
    for {
      select {
      case <-ctx.Done():
        return
      case <-ticker.C:
        httpClient.Ingest(event.Event{
          Type: "heartbeat",
          TS:   time.Now().UTC(),
          Data: map[string]interface{}{"router_id": cfg.RouterID},
        })
      }
    }
  }()

  // DNS tail + correlate
  dnsLines := make(chan string, cfg.QueueDepth)
  dnsCorr := dns.NewCorrelator(cfg, m)
  go dns.Tail(ctx, cfg.DNSMasqLogPath, dnsLines, m)
  go dnsCorr.Start(ctx, dnsLines, eventCh)

  // NFLOG
  for _, group := range cfg.NFLogGroups {
    hook := "INPUT"
    if group == 11 {
      hook = "FORWARD"
    }
    if err := nflog.Start(ctx, group, hook, m, eventCh); err != nil {
      log.Printf("nflog start failed for group %d: %v", group, err)
    }
  }

  // Conntrack
  ctCollector := conntrack.New(cfg, m, dnsCorr)
  if err := ctCollector.Start(ctx, eventCh); err != nil {
    log.Printf("conntrack start failed: %v", err)
  }

  ticker := time.NewTicker(2 * time.Second)
  defer ticker.Stop()
  for {
    select {
    case <-ctx.Done():
      close(eventCh)
      return
    case <-ticker.C:
      m.SpoolBytes.Set(float64(sp.SizeBytes()))
      m.SpoolBatches.Set(float64(sp.Count()))
      m.QueueDepth.WithLabelValues("events").Set(float64(len(eventCh)))
      m.QueueDepth.WithLabelValues("dns_lines").Set(float64(len(dnsLines)))
      m.QueueDepth.WithLabelValues("http_batch").Set(float64(httpClient.QueueDepth()))
    }
  }
}
