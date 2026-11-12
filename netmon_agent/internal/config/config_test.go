package config

import (
	"strings"
	"testing"
)

func TestTransportValidation(t *testing.T) {
	tests := []struct {
		name     string
		endpoint string
		insecure bool
		token    string
		valid    bool
	}{
		{"https", "https://netmon.example", false, strings.Repeat("a", 32), true},
		{"plaintext denied", "http://netmon.example", false, strings.Repeat("a", 32), false},
		{"explicit development", "http://127.0.0.1:3000", true, strings.Repeat("a", 32), true},
		{"other schemes denied", "ftp://netmon.example", true, strings.Repeat("a", 32), false},
		{"relative denied", "/netmon", false, strings.Repeat("a", 32), false},
		{"userinfo denied", "https://name:password@netmon.example", false, strings.Repeat("a", 32), false},
		{"query denied", "https://netmon.example?token=value", false, strings.Repeat("a", 32), false},
		{"fragment denied", "https://netmon.example#fragment", false, strings.Repeat("a", 32), false},
		{"weak token denied", "https://netmon.example", false, "replace-me", false},
		{"empty token denied", "https://netmon.example", false, "", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cfg := Config{RouterID: "router-1", RailsBaseURL: tt.endpoint, AuthToken: tt.token, NFLogGroups: []int{10}, DevelopmentAllowInsecureHTTP: tt.insecure}
			cfg.applyDefaults()
			err := cfg.validate()
			if (err == nil) != tt.valid {
				t.Fatalf("valid=%v, error=%v", tt.valid, err)
			}
		})
	}
}
