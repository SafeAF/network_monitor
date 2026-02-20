package dns

import (
  "errors"
  "regexp"
  "strings"
  "time"
)

// Example dnsmasq log lines:
// Feb 20 14:21:33 dnsmasq[1234]: query[A] example.com from 192.168.1.50
// Feb 20 14:21:33 dnsmasq[1234]: forwarded example.com to 1.1.1.1
// Feb 20 14:21:33 dnsmasq[1234]: reply example.com is 93.184.216.34
// Feb 20 14:21:33 dnsmasq[1234]: cached example.com is 93.184.216.34
// Feb 20 14:21:33 dnsmasq[1234]: query[AAAA] example.com from 192.168.1.50
// Feb 20 14:21:33 dnsmasq[1234]: reply example.com is NXDOMAIN

var (
  queryRe = regexp.MustCompile(`^(?P<ts>\w{3}\s+\d+\s+\d{2}:\d{2}:\d{2})\s+\S+\s+dnsmasq\[\d+\]:\s+query\[(?P<qtype>[^\]]+)\]\s+(?P<qname>\S+)\s+from\s+(?P<client>\S+)`)
  replyRe = regexp.MustCompile(`^(?P<ts>\w{3}\s+\d+\s+\d{2}:\d{2}:\d{2})\s+\S+\s+dnsmasq\[\d+\]:\s+reply\s+(?P<qname>\S+)\s+is\s+(?P<answer>\S+)`)
)

type ParsedLine struct {
  TS       time.Time
  Action   string
  ClientIP string
  QName    string
  QType    string
  NXDomain bool
}

func Parse(line string, now time.Time) (*ParsedLine, error) {
  line = strings.TrimSpace(line)
  if line == "" {
    return nil, errors.New("empty")
  }
  if m := queryRe.FindStringSubmatch(line); m != nil {
    ts, err := parseTS(m[1], now)
    if err != nil {
      return nil, err
    }
    return &ParsedLine{TS: ts, Action: "query", QType: m[2], QName: m[3], ClientIP: m[4]}, nil
  }
  if m := replyRe.FindStringSubmatch(line); m != nil {
    ts, err := parseTS(m[1], now)
    if err != nil {
      return nil, err
    }
    nxd := strings.Contains(strings.ToUpper(m[3]), "NXDOMAIN")
    return &ParsedLine{TS: ts, Action: "reply", QName: m[2], NXDomain: nxd}, nil
  }
  return nil, errors.New("unmatched")
}

func parseTS(prefix string, now time.Time) (time.Time, error) {
  // dnsmasq logs don't include year
  t, err := time.ParseInLocation("Jan 2 15:04:05", prefix, time.Local)
  if err != nil {
    return time.Time{}, err
  }
  return time.Date(now.Year(), t.Month(), t.Day(), t.Hour(), t.Minute(), t.Second(), 0, time.Local), nil
}
