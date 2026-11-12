package httpclient

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"netmon_agent/internal/event"
	"netmon_agent/internal/spool"
)

func TestAcknowledgementIntegrity(t *testing.T) {
	payload := []byte(`{"events":[{},{}]}`)
	tests := []struct {
		name, body         string
		success, permanent bool
	}{
		{"accepted and duplicate", `{"protocol_version":1,"accepted":2,"rejected":0,"retryable":0,"results":[{"index":0,"status":"accepted"},{"index":1,"status":"duplicate"}]}`, true, false},
		{"legacy body", `{"accepted":2,"rejected":0}`, false, false},
		{"missing result", `{"protocol_version":1,"accepted":1,"results":[{"index":0,"status":"accepted"}]}`, false, false},
		{"duplicate indices", `{"protocol_version":1,"accepted":2,"results":[{"index":0,"status":"accepted"},{"index":0,"status":"accepted"}]}`, false, false},
		{"missing index", `{"protocol_version":1,"accepted":2,"results":[{"status":"accepted"},{"index":1,"status":"accepted"}]}`, false, false},
		{"wrong counts", `{"protocol_version":1,"accepted":0,"results":[{"index":0,"status":"accepted"},{"index":1,"status":"accepted"}]}`, false, false},
		{"retryable retains batch", `{"protocol_version":1,"accepted":1,"retryable":1,"results":[{"index":0,"status":"duplicate"},{"index":1,"status":"retryable"}]}`, false, false},
		{"permanent rejection", `{"protocol_version":1,"accepted":1,"rejected":1,"results":[{"index":0,"status":"duplicate"},{"index":1,"status":"rejected"}]}`, false, true},
		{"mixed retry and permanent", `{"protocol_version":1,"retryable":1,"rejected":1,"results":[{"index":0,"status":"retryable"},{"index":1,"status":"rejected"}]}`, false, false},
		{"unknown status", `{"protocol_version":1,"results":[{"index":0,"status":"unknown"},{"index":1,"status":"unknown"}]}`, false, false},
		{"invalid JSON", `not json`, false, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := checkAcknowledgement(payload, []byte(tt.body))
			if (err == nil) != tt.success {
				t.Fatalf("unexpected result: %v", err)
			}
			var rejected *permanentRejection
			if errors.As(err, &rejected) != tt.permanent {
				t.Fatalf("wrong permanence: %v", err)
			}
		})
	}
}

func TestPermanentHTTPRejectionRequiresKnownProtocol(t *testing.T) {
	for _, status := range []int{400, 413, 422} {
		err := permanentHTTPRejection(status, []byte(`{"protocol_version":1,"error":"invalid_batch","retryable":false}`))
		var rejected *permanentRejection
		if !errors.As(err, &rejected) {
			t.Fatal("did not recognize structured rejection")
		}
	}
	for _, status := range []int{401, 403, 429, 500} {
		err := permanentHTTPRejection(status, []byte(`{"protocol_version":1,"error":"invalid_batch","retryable":false}`))
		var rejected *permanentRejection
		if errors.As(err, &rejected) {
			t.Fatal("classified configuration/transient failure as permanent")
		}
	}
	var rejected *permanentRejection
	if errors.As(permanentHTTPRejection(400, []byte(`{"error":"invalid_batch"}`)), &rejected) {
		t.Fatal("trusted an unversioned rejection")
	}
}

func testClient(t *testing.T, handler http.HandlerFunc) (*Client, string) {
	t.Helper()
	dir := t.TempDir()
	queue := spool.New(dir, 1024*1024)
	if err := queue.Ensure(); err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)
	return New(server.URL, "token", 250, time.Second, nil, queue, 10, time.Second, 1, time.Millisecond, 1, time.Second), dir
}

func TestReplayRetainsUntilEveryEventIsAcknowledged(t *testing.T) {
	var complete atomic.Bool
	client, _ := testClient(t, func(w http.ResponseWriter, r *http.Request) {
		if complete.Load() {
			fmt.Fprint(w, `{"protocol_version":1,"accepted":1,"results":[{"index":0,"status":"duplicate"}]}`)
		} else {
			fmt.Fprint(w, `{"protocol_version":1,"retryable":1,"results":[{"index":0,"status":"retryable"}]}`)
		}
	})
	payload := []byte(`{"router_id":"r","events":[{"id":"stable-id","type":"heartbeat"}]}`)
	if err := client.spool.Enqueue(payload); err != nil {
		t.Fatal(err)
	}
	client.replaySpool(context.Background(), "r")
	if client.spool.Count() != 1 {
		t.Fatal("removed a retryable batch")
	}
	complete.Store(true)
	client.replaySpool(context.Background(), "r")
	if client.spool.Count() != 0 {
		t.Fatal("did not acknowledge a complete batch")
	}
}

func TestReplayQuarantinesPoisonBatchAndContinues(t *testing.T) {
	var requests atomic.Int32
	client, dir := testClient(t, func(w http.ResponseWriter, r *http.Request) {
		requests.Add(1)
		fmt.Fprint(w, `{"protocol_version":1,"accepted":1,"results":[{"index":0,"status":"accepted"}]}`)
	})
	if err := os.WriteFile(filepath.Join(dir, "batch_000.json"), []byte("corrupt"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := client.spool.Enqueue([]byte(`{"router_id":"r","events":[{}]}`)); err != nil {
		t.Fatal(err)
	}
	client.replaySpool(context.Background(), "r")
	if client.spool.Count() != 0 || requests.Load() != 1 {
		t.Fatal("corrupt oldest file blocked valid replay")
	}
	files, _ := filepath.Glob(filepath.Join(dir, "quarantine_*.json"))
	if len(files) != 1 {
		t.Fatal("corrupt file was not preserved in quarantine")
	}
}

func TestPermanentRejectionIsPreservedBeforePendingFileIsRemoved(t *testing.T) {
	client, dir := testClient(t, func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, `{"protocol_version":1,"rejected":1,"results":[{"index":0,"status":"rejected","code":"invalid_ip"}]}`)
	})
	payload := []byte(`{"router_id":"r","events":[{"id":"bad-event"}]}`)
	if err := client.spool.Enqueue(payload); err != nil {
		t.Fatal(err)
	}
	client.replaySpool(context.Background(), "r")
	if client.spool.Count() != 0 {
		t.Fatal("permanent rejection still blocks replay")
	}
	files, _ := filepath.Glob(filepath.Join(dir, "quarantine_*.json"))
	if len(files) != 1 {
		t.Fatal("rejection was discarded")
	}
	data, err := os.ReadFile(files[0])
	if err != nil || !strings.Contains(string(data), "bad-event") || !strings.Contains(string(data), "invalid_ip") {
		t.Fatal("lost original event identity")
	}
}

func TestLiveIngestAllocatesStableIdentityBeforeSending(t *testing.T) {
	client := New("https://example.test", "token", 10, time.Second, nil, nil, 10, time.Second, 1, time.Second, 1, time.Second)
	if !client.Ingest(event.Event{Type: "heartbeat", TS: time.Now()}) {
		t.Fatal("queue rejected event")
	}
	queued := <-client.inCh
	if queued.ID == "" {
		t.Fatal("queued event has no identity")
	}
	encoded, _ := json.Marshal(queued)
	var replayed event.Event
	if err := json.Unmarshal(encoded, &replayed); err != nil {
		t.Fatal(err)
	}
	if err := replayed.EnsureID(); err != nil || replayed.ID != queued.ID {
		t.Fatal("identity changed during replay")
	}
}
