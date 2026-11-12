package spool

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"
)

func TestConcurrentWritesAreCompleteAndPrivate(t *testing.T) {
	queue := New(t.TempDir(), 1024*1024)
	if err := queue.Ensure(); err != nil {
		t.Fatal(err)
	}
	var workers sync.WaitGroup
	for i := 0; i < 20; i++ {
		workers.Add(1)
		go func(id int) {
			defer workers.Done()
			if err := queue.Enqueue([]byte(fmt.Sprintf(`{"id":%d}`, id))); err != nil {
				t.Error(err)
			}
		}(i)
	}
	workers.Wait()
	if queue.Count() != 20 {
		t.Fatal("concurrent writes collided")
	}
	for i := 0; i < 20; i++ {
		path, data, err := queue.DequeueOldest()
		if err != nil || !json.Valid(data) {
			t.Fatal("incomplete committed file", err)
		}
		info, err := os.Stat(path)
		if err != nil {
			t.Fatal(err)
		}
		if runtime.GOOS != "windows" && info.Mode().Perm() != 0o600 {
			t.Fatal("spool file is not private")
		}
		if err := queue.Ack(path); err != nil {
			t.Fatal(err)
		}
	}
	entries, _ := os.ReadDir(queue.dir)
	if len(entries) != 0 {
		t.Fatal("temporary files left behind")
	}
}

func TestOversizedLegacyFileIsNeverAcknowledgedFromTruncatedBytes(t *testing.T) {
	dir := t.TempDir()
	queue := New(dir, 10*1024*1024)
	if err := queue.Ensure(); err != nil {
		t.Fatal(err)
	}
	original := filepath.Join(dir, "batch_legacy.json")
	if err := os.WriteFile(original, []byte(strings.Repeat("x", 4*1024*1024+1)), 0o600); err != nil {
		t.Fatal(err)
	}
	path, payload, err := queue.DequeueOldest()
	if path != original || payload != nil || !errors.Is(err, ErrOversizedBatch) {
		t.Fatal("oversized file was truncated into a replayable payload")
	}
	if info, err := os.Stat(original); err != nil || info.Size() != 4*1024*1024+1 {
		t.Fatal("original oversized file was changed")
	}
}

func TestImpossibleWriteDoesNotEvictPendingData(t *testing.T) {
	queue := New(t.TempDir(), 10240)
	if err := queue.Ensure(); err != nil {
		t.Fatal(err)
	}
	if err := queue.Enqueue([]byte("original")); err != nil {
		t.Fatal(err)
	}
	if queue.Enqueue([]byte(strings.Repeat("x", 10240))) == nil {
		t.Fatal("accepted oversized write")
	}
	_, data, err := queue.DequeueOldest()
	if err != nil || string(data) != "original" {
		t.Fatal("impossible write evicted existing data")
	}
}

func TestQuarantineHasSeparateBoundedCapacity(t *testing.T) {
	queue := New(t.TempDir(), 10240)
	if err := queue.Ensure(); err != nil {
		t.Fatal(err)
	}
	if err := queue.Enqueue([]byte(strings.Repeat("p", 8000))); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 30; i++ {
		if err := queue.Quarantine([]byte("corrupt input"), "corrupt_spool"); err != nil {
			t.Fatal(err)
		}
	}
	if queue.Count() != 1 || queue.SizeBytes() > 10240 {
		t.Fatal("quarantine exceeded disk budget or evicted pending telemetry")
	}
}

func TestStartupQuarantinesIncompleteTemporaryFiles(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, ".pending-crash"), []byte("partial"), 0o600); err != nil {
		t.Fatal(err)
	}
	queue := New(dir, 10240)
	if err := queue.Ensure(); err != nil {
		t.Fatal(err)
	}
	if queue.Count() != 0 {
		t.Fatal("incomplete write entered replay queue")
	}
	files, _ := filepath.Glob(filepath.Join(dir, "quarantine_*.json"))
	if len(files) != 1 {
		t.Fatal("incomplete crash file was discarded")
	}
	if _, err := os.Stat(filepath.Join(dir, ".pending-crash")); !os.IsNotExist(err) {
		t.Fatal("temporary file was not retired")
	}
}

func TestStartupRecoversCompleteWriteBeforeRename(t *testing.T) {
	dir := t.TempDir()
	payload := []byte(`{"router_id":"r","events":[{"id":"stable-id"}]}`)
	if err := os.WriteFile(filepath.Join(dir, ".pending-crash"), payload, 0o600); err != nil {
		t.Fatal(err)
	}
	queue := New(dir, 10240)
	if err := queue.Ensure(); err != nil {
		t.Fatal(err)
	}
	if queue.Count() != 1 {
		t.Fatal("complete pending write was lost")
	}
	_, recovered, err := queue.DequeueOldest()
	if err != nil || string(recovered) != string(payload) {
		t.Fatal("recovery changed payload identity")
	}
}

func TestAckCannotDeleteFilesOutsideItsQueue(t *testing.T) {
	queue := New(t.TempDir(), 10240)
	if err := queue.Ensure(); err != nil {
		t.Fatal(err)
	}
	external := filepath.Join(t.TempDir(), "batch_external.json")
	if err := os.WriteFile(external, []byte("private"), 0o600); err != nil {
		t.Fatal(err)
	}
	if queue.Ack(external) == nil {
		t.Fatal("acknowledgement escaped spool directory")
	}
	if _, err := os.Stat(external); err != nil {
		t.Fatal("external file was removed")
	}
}
