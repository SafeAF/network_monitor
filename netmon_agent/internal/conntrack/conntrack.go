//go:build linux

package conntrack

import (
  "context"
  "fmt"
  "log"
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
  go c.run(ctx, out)
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
    State:       conntrackState(ev),
    Flags:       conntrackFlags(ev),
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

func (c *Collector) run(ctx context.Context, out chan<- event.Event) {
  backoff := 1 * time.Second
  maxBackoff := 30 * time.Second

  for {
    if ctx.Err() != nil {
      return
    }

    conn, err := ct.Dial(nil)
    if err != nil {
      log.Printf("conntrack dial failed: %v", err)
      time.Sleep(backoff)
      backoff = nextBackoff(backoff, maxBackoff)
      continue
    }

    evCh := make(chan ct.Event, 1024)
    errCh, err := conn.Listen(evCh, 1, netfilter.GroupsCT)
    if err != nil {
      _ = conn.Close()
      log.Printf("conntrack listen failed: %v", err)
      time.Sleep(backoff)
      backoff = nextBackoff(backoff, maxBackoff)
      continue
    }

    backoff = 1 * time.Second

    done := make(chan struct{})
    go func() {
      defer close(done)
      for ev := range evCh {
        if ev.Type == ct.EventDestroy || (ev.Type == ct.EventNew && c.cfg.EmitConntrackNew) {
          c.handleEvent(ev, out)
        }
      }
    }()

    select {
    case <-ctx.Done():
      _ = conn.Close()
      return
    case err := <-errCh:
      _ = conn.Close()
      log.Printf("conntrack stream error: %v", err)
      <-done
    }
  }
}

func nextBackoff(cur, max time.Duration) time.Duration {
  next := cur * 2
  if next > max {
    return max
  }
  return next
}

func conntrackState(ev ct.Event) string {
  if ev.Flow != nil && ev.Flow.ProtoInfo.TCP != nil {
    return tcpStateName(ev.Flow.ProtoInfo.TCP.State)
  }
  switch ev.Type {
  case ct.EventNew:
    return "NEW"
  case ct.EventDestroy:
    return "DESTROY"
  default:
    return ev.Type.String()
  }
}

func conntrackFlags(ev ct.Event) string {
  parts := []string{}
  if ev.Flow != nil {
    if s := ev.Flow.Status.String(); s != "" && s != "NONE" {
      parts = append(parts, s)
    }
    if ev.Flow.ProtoInfo.TCP != nil {
      of := ev.Flow.ProtoInfo.TCP.OriginalFlags
      rf := ev.Flow.ProtoInfo.TCP.ReplyFlags
      if of != 0 || rf != 0 {
        parts = append(parts, fmt.Sprintf("TCP_FLAGS=%s/%s", tcpFlagNames(of), tcpFlagNames(rf)))
      }
    }
  }
  if len(parts) == 0 {
    return ""
  }
  return joinParts(parts)
}

func joinParts(parts []string) string {
  if len(parts) == 1 {
    return parts[0]
  }
  out := parts[0]
  for i := 1; i < len(parts); i++ {
    out += "|" + parts[i]
  }
  return out
}

func tcpStateName(state uint8) string {
  switch state {
  case 1:
    return "SYN_SENT"
  case 2:
    return "SYN_RECV"
  case 3:
    return "ESTABLISHED"
  case 4:
    return "FIN_WAIT"
  case 5:
    return "CLOSE_WAIT"
  case 6:
    return "LAST_ACK"
  case 7:
    return "TIME_WAIT"
  case 8:
    return "CLOSE"
  case 9:
    return "LISTEN"
  default:
    return fmt.Sprintf("TCP_STATE_%d", state)
  }
}

func tcpFlagNames(flags uint16) string {
  if flags == 0 {
    return "NONE"
  }
  names := []struct {
    bit  uint16
    name string
  }{
    {0x01, "FIN"},
    {0x02, "SYN"},
    {0x04, "RST"},
    {0x08, "PSH"},
    {0x10, "ACK"},
    {0x20, "URG"},
    {0x40, "ECE"},
    {0x80, "CWR"},
  }
  out := []string{}
  for _, n := range names {
    if flags&n.bit != 0 {
      out = append(out, n.name)
    }
  }
  if len(out) == 0 {
    return fmt.Sprintf("0x%x", flags)
  }
  return joinParts(out)
}
