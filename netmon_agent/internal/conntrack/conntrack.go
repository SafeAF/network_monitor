//go:build linux

package conntrack

import (
  "context"
  "time"

  ct "github.com/ti-mo/conntrack"
  "github.com/ti-mo/netfilter"

  "netmon_agent/internal/config"
  "netmon_agent/internal/event"
  "netmon_agent/internal/metrics"
  "netmon_agent/internal/dns"
  "netmon_agent/internal/util"
)

type Collector struct {
  cfg     *config.Config
  metrics *metrics.Metrics
  dns     *dns.Correlator
}

func New(cfg *config.Config, metrics *metrics.Metrics, dns *dns.Correlator) *Collector {
  return &Collector{cfg: cfg, metrics: metrics, dns: dns}
}

func (c *Collector) Start(ctx context.Context, out chan<- event.Event) error {
  conn, err := ct.Dial(nil)
  if err != nil {
    return err
  }
  go func() {
    <-ctx.Done()
    _ = conn.Close()
  }()

  evCh := make(chan ct.Event, 1024)
  errCh, err := conn.Listen(evCh, 1, netfilter.GroupsCT)
  if err != nil {
    return err
  }
  go func() {
    for err := range errCh {
      _ = err
    }
  }()
  go func() {
    for ev := range evCh {
      if ev.Type == ct.EventDestroy || (ev.Type == ct.EventNew && c.cfg.EmitConntrackNew) {
        c.handleEvent(ev, out)
      }
    }
  }()

  return nil
}

func (c *Collector) handleEvent(ev ct.Event, out chan<- event.Event) {
  if ev.Flow == nil {
    c.metrics.ConntrackParseErrors.Inc()
    return
  }
  if ev.Type == ct.EventDestroy {
    c.metrics.ConntrackDestroy.Inc()
  }

  srcIP := ev.Flow.TupleOrig.IP.SourceAddress.String()
  dstIP := ev.Flow.TupleOrig.IP.DestinationAddress.String()
  srcPort := int(ev.Flow.TupleOrig.Proto.SourcePort)
  dstPort := int(ev.Flow.TupleOrig.Proto.DestinationPort)
  l4proto := int(ev.Flow.TupleOrig.Proto.Protocol)

  firstSeen := time.Now().UTC()
  lastSeen := time.Now().UTC()
  // conntrack v0.6.0 doesn't expose per-flow first/last seen timestamps; keep now.

  flow := event.Flow{
    Event:       ev.Type.String(),
    SrcIP:       srcIP,
    DstIP:       dstIP,
    SrcPort:     srcPort,
    DstPort:     dstPort,
    L4Proto:     l4proto,
    Dir:         "OUT",
    BytesOrig:   ev.Flow.CountersOrig.Bytes,
    BytesReply:  ev.Flow.CountersReply.Bytes,
    PacketsOrig: ev.Flow.CountersOrig.Packets,
    PacketsReply: ev.Flow.CountersReply.Packets,
    FirstSeen:   firstSeen,
    LastSeen:    lastSeen,
  }

  if c.dns != nil {
    flow.DNSContext = c.dns.DNSContextForIP(srcIP)
  }

  util.TrySend(out, c.metrics, "flow", event.Event{Type: "flow", TS: time.Now().UTC(), Data: flow})
}
