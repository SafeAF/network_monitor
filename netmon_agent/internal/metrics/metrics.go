package metrics

import "github.com/prometheus/client_golang/prometheus"

type Metrics struct {
  NFLogEventsTotal    *prometheus.CounterVec
  NFLogParseErrors    prometheus.Counter
  ConntrackDestroy    prometheus.Counter
  ConntrackParseErrors prometheus.Counter
  DNSLinesTotal       prometheus.Counter
  DNSParseErrors      prometheus.Counter
  DNSBucketsEmitted   prometheus.Counter
  QueueDepth          *prometheus.GaugeVec
  DroppedLocalTotal   *prometheus.CounterVec
  HTTPBatchesSent     prometheus.Counter
  HTTPSendErrors      *prometheus.CounterVec
  SpoolBytes          prometheus.Gauge
  SpoolBatches        prometheus.Gauge
  SpoolDroppedTotal   prometheus.Counter
}

func New() *Metrics {
  m := &Metrics{
    NFLogEventsTotal: prometheus.NewCounterVec(prometheus.CounterOpts{
      Name: "nflog_events_total",
      Help: "NFLOG events observed",
    }, []string{"group", "tag"}),
    NFLogParseErrors: prometheus.NewCounter(prometheus.CounterOpts{
      Name: "nflog_parse_errors_total",
      Help: "NFLOG parse errors",
    }),
    ConntrackDestroy: prometheus.NewCounter(prometheus.CounterOpts{
      Name: "conntrack_destroy_total",
      Help: "Conntrack destroy events",
    }),
    ConntrackParseErrors: prometheus.NewCounter(prometheus.CounterOpts{
      Name: "conntrack_parse_errors_total",
      Help: "Conntrack parse errors",
    }),
    DNSLinesTotal: prometheus.NewCounter(prometheus.CounterOpts{
      Name: "dns_lines_total",
      Help: "DNS log lines processed",
    }),
    DNSParseErrors: prometheus.NewCounter(prometheus.CounterOpts{
      Name: "dns_parse_errors_total",
      Help: "DNS parse errors",
    }),
    DNSBucketsEmitted: prometheus.NewCounter(prometheus.CounterOpts{
      Name: "dns_buckets_emitted_total",
      Help: "DNS buckets emitted",
    }),
    QueueDepth: prometheus.NewGaugeVec(prometheus.GaugeOpts{
      Name: "queue_depth",
      Help: "Queue depth by stream",
    }, []string{"stream"}),
    DroppedLocalTotal: prometheus.NewCounterVec(prometheus.CounterOpts{
      Name: "events_dropped_local_total",
      Help: "Events dropped locally due to backpressure",
    }, []string{"stream"}),
    HTTPBatchesSent: prometheus.NewCounter(prometheus.CounterOpts{
      Name: "http_batches_sent_total",
      Help: "HTTP batches sent",
    }),
    HTTPSendErrors: prometheus.NewCounterVec(prometheus.CounterOpts{
      Name: "http_send_errors_total",
      Help: "HTTP send errors",
    }, []string{"code"}),
    SpoolBytes: prometheus.NewGauge(prometheus.GaugeOpts{
      Name: "spool_bytes",
      Help: "Spool size in bytes",
    }),
    SpoolBatches: prometheus.NewGauge(prometheus.GaugeOpts{
      Name: "spool_batches",
      Help: "Spool batches count",
    }),
    SpoolDroppedTotal: prometheus.NewCounter(prometheus.CounterOpts{
      Name: "spool_dropped_batches_total",
      Help: "Spool dropped batches",
    }),
  }

  prometheus.MustRegister(
    m.NFLogEventsTotal,
    m.NFLogParseErrors,
    m.ConntrackDestroy,
    m.ConntrackParseErrors,
    m.DNSLinesTotal,
    m.DNSParseErrors,
    m.DNSBucketsEmitted,
    m.QueueDepth,
    m.DroppedLocalTotal,
    m.HTTPBatchesSent,
    m.HTTPSendErrors,
    m.SpoolBytes,
    m.SpoolBatches,
    m.SpoolDroppedTotal,
  )

  return m
}
