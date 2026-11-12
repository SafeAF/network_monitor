package dns

import (
	"strings"
	"testing"
	"time"
)

func TestParseValidDNSLogSamples(t *testing.T) {
	now := time.Date(2026, 11, 12, 12, 0, 1, 0, time.Local)
	samples := []string{
		"Nov 12 12:00:00 dnsmasq[1]: query[A] example.com from 10.0.0.20",
		"Nov 12 12:00:00 router dnsmasq[1]: query[AAAA] example.com from 2001:db8::20",
		"Nov 12 12:00:00 dnsmasq[1]: forwarded example.com to 1.1.1.1",
		"Nov 12 12:00:00 dnsmasq[1]: cached example.com is 203.0.113.8",
	}
	for _, line := range samples {
		if _, err := Parse(line, now); err != nil {
			t.Fatalf("valid sample rejected: %v", err)
		}
	}
}

func TestParseRejectsOversizedOrMalformedDNSFields(t *testing.T) {
	now := time.Date(2026, 11, 12, 12, 0, 1, 0, time.Local)
	samples := []string{
		strings.Repeat("x", maxDNSLogLine+1),
		"Nov 12 12:00:00 dnsmasq[1]: query[A] " + strings.Repeat("x", 254) + " from 10.0.0.20",
		"Nov 12 12:00:00 dnsmasq[1]: query[" + strings.Repeat("A", 17) + "] example.com from 10.0.0.20",
		"Nov 12 12:00:00 dnsmasq[1]: query[A] example.com from invalid-address",
		"Nov 12 12:00:00 dnsmasq[1]: reply example.com is " + strings.Repeat("x", 1025),
		"Nov 12 12:00:00 dnsmasq[1]: forwarded example.com to " + strings.Repeat("x", 256),
	}
	for _, line := range samples {
		if _, err := Parse(line, now); err == nil {
			t.Fatal("invalid sample accepted")
		}
	}
}

func TestParseRotatedDecemberLineUsesPreviousYearInJanuary(t *testing.T) {
	now := time.Date(2026, 1, 1, 0, 0, 1, 0, time.Local)
	parsed, err := Parse("Dec 31 23:59:59 dnsmasq[1]: query[A] example.com from 10.0.0.20", now)
	if err != nil || parsed.TS.Year() != 2025 {
		t.Fatalf("wrong year at rotation boundary: %#v, %v", parsed, err)
	}
}
