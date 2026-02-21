//go:build linux

package nflog

import (
  "context"
  "net"
  "strconv"
  "time"

  nflog "github.com/florianl/go-nflog"
  "github.com/google/gopacket"
  "github.com/google/gopacket/layers"

  "netmon_agent/internal/event"
  "netmon_agent/internal/metrics"
  "netmon_agent/internal/util"
)

type Handler struct {
  group   int
  hook    string
  metrics *metrics.Metrics
  out     chan<- event.Event
}

func Start(ctx context.Context, group int, hook string, metrics *metrics.Metrics, out chan<- event.Event) error {
  h := &Handler{group: group, hook: hook, metrics: metrics, out: out}
  cfg := nflog.Config{Group: uint16(group), Copymode: nflog.NfUlnlCopyPacket, Bufsize: 128}
  n, err := nflog.Open(&cfg)
  if err != nil {
    return err
  }
  go func() {
    <-ctx.Done()
    _ = n.Close()
  }()
  return n.Register(ctx, h.cb)
}

func (h *Handler) cb(m nflog.Msg) int {
  defer func() {
    if recover() != nil {
      h.metrics.NFLogParseErrors.Inc()
    }
  }()
  raw, ok := m[nflog.AttrPayload].([]byte)
  if !ok || len(raw) == 0 {
    return 0
  }
  pkt := gopacket.NewPacket(raw, layers.LayerTypeIPv4, gopacket.Default)
  ipLayer := pkt.Layer(layers.LayerTypeIPv4)
  if ipLayer == nil {
    h.metrics.NFLogParseErrors.Inc()
    return 0
  }
  ip := ipLayer.(*layers.IPv4)

  var srcPort, dstPort int
  var l4proto int
  var tcpSyn bool

  if tcpLayer := pkt.Layer(layers.LayerTypeTCP); tcpLayer != nil {
    tcp := tcpLayer.(*layers.TCP)
    srcPort = int(tcp.SrcPort)
    dstPort = int(tcp.DstPort)
    l4proto = 6
    tcpSyn = tcp.SYN
  } else if udpLayer := pkt.Layer(layers.LayerTypeUDP); udpLayer != nil {
    udp := udpLayer.(*layers.UDP)
    srcPort = int(udp.SrcPort)
    dstPort = int(udp.DstPort)
    l4proto = 17
  } else {
    l4proto = int(ip.Protocol)
  }

  var ifIn, ifOut string
  if idx, ok := m[nflog.AttrIfindexIndev].(uint32); ok {
    if iface, err := net.InterfaceByIndex(int(idx)); err == nil {
      ifIn = iface.Name
    }
  }
  if idx, ok := m[nflog.AttrIfindexOutdev].(uint32); ok {
    if iface, err := net.InterfaceByIndex(int(idx)); err == nil {
      ifOut = iface.Name
    }
  }

  tag := ""
  if pfx, ok := m[nflog.AttrPrefix].(string); ok {
    tag = pfx
  }

  h.metrics.NFLogEventsTotal.WithLabelValues(strconv.Itoa(h.group), tag).Inc()

  var ifOutPtr *string
  if ifOut != "" {
    ifOutPtr = &ifOut
  }

  util.TrySend(h.out, h.metrics, "firewall_drop", event.Event{Type: "firewall_drop", TS: time.Now().UTC(), Data: event.FirewallDrop{
    Hook: h.hook,
    RuleTag: tag,
    NflogGroup: h.group,
    IfIn: ifIn,
    IfOut: ifOutPtr,
    SrcIP: ip.SrcIP.String(),
    DstIP: ip.DstIP.String(),
    SrcPort: srcPort,
    DstPort: dstPort,
    L4Proto: l4proto,
    TCPSyn: tcpSyn,
  }})

  return 0
}
