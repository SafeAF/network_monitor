package dns

import (
	"context"
	"testing"
	"time"

	"netmon_agent/internal/config"
	"netmon_agent/internal/event"
)

func TestCorrelatorParsesRouterLogFormatWithoutHostname(t *testing.T) {
	corr := NewCorrelator(&config.Config{QnameHashCap: 8}, nil)
	lines := make(chan string, 8)
	out := make(chan event.Event, 4)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go corr.Start(ctx, lines, out)

	lines <- "Mar 15 16:07:32 dnsmasq[3328]: query[A] whois.arin.net from 10.0.0.10"
	lines <- "Mar 15 16:07:32 dnsmasq[3328]: cached whois.arin.net is 199.71.0.46"
	lines <- "Mar 15 16:07:32 dnsmasq[3328]: cached whois.arin.net is 199.5.26.46"

	ev := waitForEvent(t, out)
	payload := assertDNSResponse(t, ev)

	if payload.ClientIP != "10.0.0.10" {
		t.Fatalf("expected client ip 10.0.0.10, got %s", payload.ClientIP)
	}
	if payload.QName != "whois.arin.net" {
		t.Fatalf("expected qname whois.arin.net, got %s", payload.QName)
	}
	if payload.QType != "A" {
		t.Fatalf("expected qtype A, got %s", payload.QType)
	}
	if len(payload.Answers) != 2 {
		t.Fatalf("expected 2 answers, got %d", len(payload.Answers))
	}
}

func TestCorrelatorKeepsSeparateAAndAAAAQueriesForSameQName(t *testing.T) {
	corr := NewCorrelator(&config.Config{QnameHashCap: 8}, nil)
	lines := make(chan string, 8)
	out := make(chan event.Event, 4)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go corr.Start(ctx, lines, out)

	lines <- "Mar 15 16:07:32 dnsmasq[3328]: query[A] whois.arin.net from 10.0.0.10"
	lines <- "Mar 15 16:07:32 dnsmasq[3328]: cached whois.arin.net is 199.71.0.46"
	lines <- "Mar 15 16:07:32 dnsmasq[3328]: query[AAAA] whois.arin.net from 10.0.0.10"
	lines <- "Mar 15 16:07:32 dnsmasq[3328]: cached whois.arin.net is 2001:500:31::46"

	first := assertDNSResponse(t, waitForEvent(t, out))
	second := assertDNSResponse(t, waitForEvent(t, out))

	seen := map[string]int{}
	for _, payload := range []event.DNSResponse{first, second} {
		seen[payload.QType]++
	}

	if seen["A"] != 1 || seen["AAAA"] != 1 {
		t.Fatalf("expected one A and one AAAA event, got %#v", seen)
	}
}

func TestCorrelatorCarriesCNAMEChainBackToOriginalQName(t *testing.T) {
	corr := NewCorrelator(&config.Config{QnameHashCap: 8}, nil)
	lines := make(chan string, 8)
	out := make(chan event.Event, 4)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go corr.Start(ctx, lines, out)

	lines <- "Mar 16 10:49:46 dnsmasq[3328]: query[A] news.ycombinator.com from 10.0.0.20"
	lines <- "Mar 16 10:49:46 dnsmasq[3328]: reply news.ycombinator.com is ycombinator.map.fastly.net"
	lines <- "Mar 16 10:49:46 dnsmasq[3328]: reply ycombinator.map.fastly.net is 151.101.1.164"

	payload := assertDNSResponse(t, waitForEvent(t, out))
	if payload.QName != "news.ycombinator.com" {
		t.Fatalf("expected original qname news.ycombinator.com, got %s", payload.QName)
	}
	if len(payload.Answers) != 1 || payload.Answers[0].Data != "151.101.1.164" {
		t.Fatalf("expected final A answer to be attached to original query, got %#v", payload.Answers)
	}
}

func TestCorrelatorEmitsNXDomainDNSResponse(t *testing.T) {
	corr := NewCorrelator(&config.Config{QnameHashCap: 8}, nil)
	lines := make(chan string, 4)
	out := make(chan event.Event, 2)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go corr.Start(ctx, lines, out)

	lines <- "Mar 15 16:07:32 dnsmasq[3328]: query[A] missing.example from 10.0.0.20"
	lines <- "Mar 15 16:07:32 dnsmasq[3328]: reply missing.example is NXDOMAIN"

	payload := assertDNSResponse(t, waitForEvent(t, out))
	if payload.RCode != "NXDOMAIN" {
		t.Fatalf("expected NXDOMAIN rcode, got %s", payload.RCode)
	}
	if len(payload.Answers) != 0 {
		t.Fatalf("expected no answers, got %d", len(payload.Answers))
	}
}

func waitForEvent(t *testing.T, out <-chan event.Event) event.Event {
	t.Helper()

	select {
	case ev := <-out:
		return ev
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for dns_response event")
		return event.Event{}
	}
}

func assertDNSResponse(t *testing.T, ev event.Event) event.DNSResponse {
	t.Helper()

	if ev.Type != "dns_response" {
		t.Fatalf("expected dns_response event, got %s", ev.Type)
	}
	payload, ok := ev.Data.(event.DNSResponse)
	if !ok {
		t.Fatalf("expected DNSResponse payload, got %T", ev.Data)
	}
	return payload
}
