//go:build linux

package conntrack

import (
  "context"
  "fmt"
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
        parts = append(parts, fmt.Sprintf("TCP_FLAGS=%#x/%#x", of, rf))
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
