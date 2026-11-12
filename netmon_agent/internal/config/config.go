package config

import (
	"errors"
	"net/url"
	"os"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

type Config struct {
	RouterID                     string   `yaml:"router_id"`
	RailsBaseURL                 string   `yaml:"rails_base_url"`
	AuthToken                    string   `yaml:"auth_token"`
	DevelopmentAllowInsecureHTTP bool     `yaml:"development_allow_insecure_http"`
	NFLogGroups                  []int    `yaml:"nflog_groups"`
	DNSMasqLogPath               string   `yaml:"dnsmasq_log_path"`
	LANInterfaces                []string `yaml:"lan_interfaces"`
	WANInterfaces                []string `yaml:"wan_interfaces"`
	LANSubnets                   []string `yaml:"lan_subnets"`
	MetricsBind                  string   `yaml:"metrics_bind"`

	BatchMaxEvents       int           `yaml:"batch_max_events"`
	BatchMaxWait         time.Duration `yaml:"batch_max_wait"`
	QueueDepth           int           `yaml:"queue_depth"`
	SpoolDir             string        `yaml:"spool_dir"`
	SpoolMaxBytes        int64         `yaml:"spool_max_bytes"`
	QnameHashSalt        string        `yaml:"qname_hash_salt"`
	QnameHashCap         int           `yaml:"qname_hash_cap"`
	EmitConntrackNew     bool          `yaml:"emit_conntrack_new"`
	HttpTimeout          time.Duration `yaml:"http_timeout"`
	HttpRetryMax         int           `yaml:"http_retry_max"`
	HttpRetryBase        time.Duration `yaml:"http_retry_base"`
	HTTPFlushWorkers     int           `yaml:"http_flush_workers"`
	SpoolReplayInterval  time.Duration `yaml:"spool_replay_interval"`
	HeartbeatInterval    time.Duration `yaml:"heartbeat_interval"`
	ConntrackReadBuffer  int           `yaml:"conntrack_read_buffer"`
	ConntrackWorkers     int           `yaml:"conntrack_workers"`
	ConntrackEventBuffer int           `yaml:"conntrack_event_buffer"`
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
	if c.HttpTimeout == 0 {
		c.HttpTimeout = 5 * time.Second
	}
	if c.HttpRetryMax == 0 {
		c.HttpRetryMax = 5
	}
	if c.HttpRetryBase == 0 {
		c.HttpRetryBase = 1 * time.Second
	}
	if c.HTTPFlushWorkers == 0 {
		c.HTTPFlushWorkers = 2
	}
	if c.SpoolReplayInterval == 0 {
		c.SpoolReplayInterval = 5 * time.Second
	}
	if c.HeartbeatInterval == 0 {
		c.HeartbeatInterval = 30 * time.Second
	}
	if c.ConntrackReadBuffer == 0 {
		c.ConntrackReadBuffer = 4 * 1024 * 1024
	}
	if c.ConntrackWorkers == 0 {
		c.ConntrackWorkers = 2
	}
	if c.ConntrackEventBuffer == 0 {
		c.ConntrackEventBuffer = 4096
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
	endpoint, err := url.Parse(c.RailsBaseURL)
	if err != nil || endpoint.Hostname() == "" || endpoint.Opaque != "" || endpoint.User != nil || endpoint.RawQuery != "" || endpoint.Fragment != "" {
		return errors.New("rails_base_url must be an absolute URL without credentials, query or fragment")
	}
	if endpoint.Scheme != "https" && !(endpoint.Scheme == "http" && c.DevelopmentAllowInsecureHTTP) {
		return errors.New("rails_base_url requires HTTPS; development_allow_insecure_http is for local development only")
	}
	if len(c.AuthToken) < 32 || strings.TrimSpace(c.AuthToken) != c.AuthToken {
		return errors.New("auth_token must contain at least 32 characters with no surrounding whitespace")
	}
	c.RailsBaseURL = strings.TrimRight(c.RailsBaseURL, "/")
	if len(c.NFLogGroups) == 0 {
		return errors.New("nflog_groups required")
	}
	if c.BatchMaxEvents < 1 || c.BatchMaxEvents > 500 || c.QueueDepth < 1 || c.QueueDepth > 100000 ||
		c.HTTPFlushWorkers < 1 || c.HTTPFlushWorkers > 16 || c.QnameHashCap < 1 || c.QnameHashCap > 256 ||
		c.SpoolMaxBytes < 1024 || c.HttpRetryMax < 1 || c.HttpRetryMax > 10 ||
		c.ConntrackWorkers < 1 || c.ConntrackWorkers > 8 || c.ConntrackEventBuffer < 1 || c.ConntrackEventBuffer > 100000 {
		return errors.New("queue, batch, spool, retry or worker setting outside supported bounds")
	}
	for _, duration := range []time.Duration{c.BatchMaxWait, c.HttpTimeout, c.HttpRetryBase, c.SpoolReplayInterval, c.HeartbeatInterval} {
		if duration <= 0 || duration > time.Minute {
			return errors.New("timing settings must be positive and at most one minute")
		}
	}
	for _, group := range c.NFLogGroups {
		if group < 0 || group > 65535 {
			return errors.New("nflog group outside uint16 range")
		}
	}
	return nil
}
