package event

import "time"

type Batch struct {
  RouterID string    `json:"router_id"`
  SentAt   time.Time `json:"sent_at"`
  Events   []Event   `json:"events"`
}

type Event struct {
  Type string      `json:"type"`
  TS   time.Time   `json:"ts"`
  Data interface{} `json:"data"`
}

type FirewallDrop struct {
  Hook       string  `json:"hook"`
  RuleTag    string  `json:"rule_tag"`
  NflogGroup int     `json:"nflog_group"`
  IfIn       string  `json:"if_in"`
  IfOut      *string `json:"if_out"`
  SrcIP      string  `json:"src_ip"`
  DstIP      string  `json:"dst_ip"`
  SrcPort    int     `json:"src_port"`
  DstPort    int     `json:"dst_port"`
  L4Proto    int     `json:"l4proto"`
  TCPSyn     bool    `json:"tcp_syn"`
}

type Flow struct {
  Event       string    `json:"event"`
  SrcIP       string    `json:"src_ip"`
  DstIP       string    `json:"dst_ip"`
  SrcPort     int       `json:"src_port"`
  DstPort     int       `json:"dst_port"`
  L4Proto     int       `json:"l4proto"`
  Dir         string    `json:"dir"`
  BytesOrig   uint64    `json:"bytes_orig"`
  BytesReply  uint64    `json:"bytes_reply"`
  PacketsOrig uint64    `json:"packets_orig"`
  PacketsReply uint64   `json:"packets_reply"`
  FirstSeen   time.Time `json:"first_seen"`
  LastSeen    time.Time `json:"last_seen"`
  DNSContext  *DNSContext `json:"dns_context,omitempty"`
}

type DNSBucket struct {
  BucketStart time.Time `json:"bucket_start"`
  ClientIP    string    `json:"client_ip"`
  QType       string    `json:"qtype"`
  QNameHash   string    `json:"qname_hash"`
  Count       int       `json:"count"`
  NXDomain    int       `json:"nxdomain"`
}

type HostIdentity struct {
  IP                string    `json:"ip"`
  LastSeen          time.Time `json:"last_seen"`
  RecentQNameHashes []string  `json:"recent_qname_hashes"`
}

type DNSContext struct {
  RecentQNameHashes []string `json:"recent_qname_hashes"`
  LastSeen          string   `json:"last_seen"`
}
