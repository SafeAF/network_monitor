package config

import (
  "errors"
  "os"
  "time"

  "gopkg.in/yaml.v3"
)

type Config struct {
  RouterID        string   `yaml:"router_id"`
  RailsBaseURL    string   `yaml:"rails_base_url"`
  AuthToken       string   `yaml:"auth_token"`
  NFLogGroups     []int    `yaml:"nflog_groups"`
  DNSMasqLogPath  string   `yaml:"dnsmasq_log_path"`
  LANInterfaces   []string `yaml:"lan_interfaces"`
  WANInterfaces   []string `yaml:"wan_interfaces"`
  LANSubnets      []string `yaml:"lan_subnets"`
  MetricsBind     string   `yaml:"metrics_bind"`

  BatchMaxEvents  int           `yaml:"batch_max_events"`
  BatchMaxWait    time.Duration `yaml:"batch_max_wait"`
  QueueDepth      int           `yaml:"queue_depth"`
  SpoolDir        string        `yaml:"spool_dir"`
  SpoolMaxBytes   int64         `yaml:"spool_max_bytes"`
  QnameHashSalt   string        `yaml:"qname_hash_salt"`
  QnameHashCap    int           `yaml:"qname_hash_cap"`
  EmitConntrackNew bool         `yaml:"emit_conntrack_new"`
}

func Load(path string) (*Config, error) {
  data, err := os.ReadFile(path)
  if err != nil {
    return nil, err
  }
  cfg := &Config{}
  if err := yaml.Unmarshal(data, cfg); err != nil {
    return nil, err
  }
  cfg.applyDefaults()
  if err := cfg.validate(); err != nil {
    return nil, err
  }
  return cfg, nil
}

func (c *Config) applyDefaults() {
  if c.MetricsBind == "" {
    c.MetricsBind = "127.0.0.1:9109"
  }
  if c.BatchMaxEvents == 0 {
    c.BatchMaxEvents = 250
  }
  if c.BatchMaxWait == 0 {
    c.BatchMaxWait = time.Second
  }
  if c.QueueDepth == 0 {
    c.QueueDepth = 2000
  }
  if c.DNSMasqLogPath == "" {
    c.DNSMasqLogPath = "/var/log/dnsmasq.log"
  }
  if c.SpoolDir == "" {
    c.SpoolDir = "/var/lib/netmon-agent/spool"
  }
  if c.SpoolMaxBytes == 0 {
    c.SpoolMaxBytes = 50 * 1024 * 1024
  }
  if c.QnameHashCap == 0 {
    c.QnameHashCap = 200
  }
}

func (c *Config) validate() error {
  if c.RouterID == "" {
    return errors.New("router_id is required")
  }
  if c.RailsBaseURL == "" {
    return errors.New("rails_base_url is required")
  }
  if c.AuthToken == "" {
    return errors.New("auth_token is required")
  }
  if len(c.NFLogGroups) == 0 {
    return errors.New("nflog_groups required")
  }
  return nil
}
