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

	lines <- "Mar 16 10:49:46 dnsmasq[3328]: query[A] tosmediaserver.schwab.com from 10.0.0.20"
	lines <- "Mar 16 10:49:46 dnsmasq[3328]: reply tosmediaserver.schwab.com is <CNAME>"
	lines <- "Mar 16 10:49:46 dnsmasq[3328]: reply tosmediaserver.gslb.schwab.com is 162.93.118.3"

	payload := assertDNSResponse(t, waitForEvent(t, out))
	if payload.QName != "tosmediaserver.schwab.com" {
		t.Fatalf("expected original qname tosmediaserver.schwab.com, got %s", payload.QName)
	}
	if len(payload.Answers) != 1 || payload.Answers[0].Data != "162.93.118.3" {
		t.Fatalf("expected final A answer to be attached to original query, got %#v", payload.Answers)
	}
}

func TestCorrelatorTransformsPTRRepliesIntoHostToIPMappings(t *testing.T) {
	corr := NewCorrelator(&config.Config{QnameHashCap: 8}, nil)
	lines := make(chan string, 8)
	out := make(chan event.Event, 4)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go corr.Start(ctx, lines, out)

	lines <- "Mar 15 16:05:38 dnsmasq[3328]: query[PTR] 207.230.216.209.in-addr.arpa from 10.0.0.10"
	lines <- "Mar 15 16:05:38 dnsmasq[3328]: forwarded 207.230.216.209.in-addr.arpa to 1.1.1.1"
	lines <- "Mar 15 16:05:38 dnsmasq[3328]: reply 209.216.230.207 is news.ycombinator.com"

	payload := assertDNSResponse(t, waitForEvent(t, out))
	if payload.ClientIP != "10.0.0.10" {
		t.Fatalf("expected client ip 10.0.0.10, got %s", payload.ClientIP)
	}
	if payload.QName != "news.ycombinator.com" {
		t.Fatalf("expected PTR hostname news.ycombinator.com, got %s", payload.QName)
	}
	if payload.QType != "PTR" {
		t.Fatalf("expected qtype PTR, got %s", payload.QType)
	}
	if len(payload.Answers) != 1 {
		t.Fatalf("expected one PTR-derived answer, got %#v", payload.Answers)
	}
	if payload.Answers[0].Data != "209.216.230.207" || payload.Answers[0].Type != "A" {
		t.Fatalf("expected PTR-derived IP answer, got %#v", payload.Answers[0])
	}
}

func TestCorrelatorHandlesIPv6PTRQueries(t *testing.T) {
	corr := NewCorrelator(&config.Config{QnameHashCap: 8}, nil)
	lines := make(chan string, 8)
	out := make(chan event.Event, 4)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go corr.Start(ctx, lines, out)

	lines <- "Feb 18 00:00:01 dnsmasq[3328]: query[PTR] c.3.9.0.d.9.e.f.f.f.8.b.b.e.e.e.0.0.0.0.0.0.0.0.0.0.0.0.0.8.e.f.ip6.arpa from 10.0.0.19"
	lines <- "Feb 18 00:00:01 dnsmasq[3328]: reply fe80::eeeb:b8ff:fe9d:93c is router.example"

	payload := assertDNSResponse(t, waitForEvent(t, out))
	if payload.QName != "router.example" {
		t.Fatalf("expected PTR hostname router.example, got %s", payload.QName)
	}
	if payload.QType != "PTR" {
		t.Fatalf("expected qtype PTR, got %s", payload.QType)
	}
	if len(payload.Answers) != 1 || payload.Answers[0].Data != "fe80::eeeb:b8ff:fe9d:93c" || payload.Answers[0].Type != "AAAA" {
		t.Fatalf("expected IPv6 PTR-derived answer, got %#v", payload.Answers)
	}
}

func TestCorrelatorDoesNotTreatNODATAAsAnAlias(t *testing.T) {
	corr := NewCorrelator(&config.Config{QnameHashCap: 8}, nil)
	lines := make(chan string, 8)
	out := make(chan event.Event, 4)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go corr.Start(ctx, lines, out)

	lines <- "Feb 18 18:51:08 dnsmasq[3328]: query[A] api.github.com from 10.0.0.25"
	lines <- "Feb 18 18:51:08 dnsmasq[3328]: reply api.github.com is NODATA"
	lines <- "Feb 18 18:51:08 dnsmasq[3328]: reply api.github.com is 140.82.116.5"

	payload := assertDNSResponse(t, waitForEvent(t, out))
	if payload.QName != "api.github.com" {
		t.Fatalf("expected qname api.github.com, got %s", payload.QName)
	}
	if len(payload.Answers) != 1 || payload.Answers[0].Data != "140.82.116.5" {
		t.Fatalf("expected final A answer after NODATA marker, got %#v", payload.Answers)
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
