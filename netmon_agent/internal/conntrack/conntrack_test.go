//go:build linux

package conntrack

import (
	"testing"

	ct "github.com/ti-mo/conntrack"

	"netmon_agent/internal/config"
)

func TestCollectorShouldEmitEvent(t *testing.T) {
	collector := New(&config.Config{}, nil, nil)

	if !collector.shouldEmitEvent(ct.Event{Type: ct.EventNew}) {
		t.Fatal("expected NEW events to be emitted")
	}
	if !collector.shouldEmitEvent(ct.Event{Type: ct.EventDestroy}) {
		t.Fatal("expected DESTROY events to be emitted")
	}
	if collector.shouldEmitEvent(ct.Event{Type: ct.EventUpdate}) {
		t.Fatal("did not expect UPDATE events to be emitted")
	}
}
