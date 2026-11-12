package spool

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"time"
)

type Spool struct {
	dir      string
	maxBytes int64
	mu       sync.Mutex
}

var ErrOversizedBatch = errors.New("spool file exceeds 4 MiB; original retained for operator recovery")

func New(dir string, maxBytes int64) *Spool {
	return &Spool{dir: dir, maxBytes: maxBytes}
}

func (s *Spool) Ensure() error {
	if s.maxBytes < 1024 {
		return errors.New("spool_max_bytes must be at least 1024")
	}
	if err := os.MkdirAll(s.dir, 0o700); err != nil {
		return err
	}
	if err := os.Chmod(s.dir, 0o700); err != nil {
		return err
	}
	// A spool directory belongs to one agent process. Recover complete writes
	// left before rename; preserve incomplete writes for operator inspection.
	entries, err := os.ReadDir(s.dir)
	if err != nil {
		return err
	}
	for _, entry := range entries {
		if strings.HasPrefix(entry.Name(), ".pending-") && entry.Type().IsRegular() {
			if err := s.recoverTemporary(filepath.Join(s.dir, entry.Name())); err != nil {
				return err
			}
		}
	}
	return nil
}

func (s *Spool) recoverTemporary(path string) error {
	file, err := os.OpenFile(path, os.O_RDWR, 0)
	if err != nil {
		return err
	}
	data, err := io.ReadAll(io.LimitReader(file, 4*1024*1024+1))
	if err != nil {
		file.Close()
		return err
	}
	if len(data) > 4*1024*1024 {
		file.Close()
		return ErrOversizedBatch
	}
	if err := file.Sync(); err != nil {
		file.Close()
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	if !json.Valid(data) {
		if err := s.Quarantine(data, "incomplete_write"); err != nil {
			return err
		}
		if err := os.Remove(path); err != nil {
			return err
		}
		return s.syncDirectory()
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.ensureCap("batch_", int64(len(data)), s.maxBytes-s.maxBytes/10); err != nil {
		return err
	}
	name := fmt.Sprintf("batch_%d_recovered_%s.json", time.Now().UnixNano(), filepath.Base(path))
	if err := os.Rename(path, filepath.Join(s.dir, name)); err != nil {
		return err
	}
	log.Printf("spool recovered complete write")
	return s.syncDirectory()
}

func (s *Spool) Enqueue(payload []byte) error {
	return s.write("batch_", payload)
}

// Quarantine never consumes the pending queue's reserved disk budget. Keep the
// original bytes (even corrupt JSON) and a fixed reason for operator inspection.
func (s *Spool) Quarantine(payload []byte, reason string, acknowledgement ...json.RawMessage) error {
	var content interface{} = string(payload)
	if json.Valid(payload) {
		content = json.RawMessage(payload)
	}
	record := map[string]interface{}{
		"reason": reason, "quarantined_at": time.Now().UTC(), "payload": content,
	}
	if len(acknowledgement) > 0 && json.Valid(acknowledgement[0]) {
		record["acknowledgement"] = acknowledgement[0]
	}
	data, err := json.Marshal(record)
	if err != nil {
		return err
	}
	return s.write("quarantine_", data)
}

func (s *Spool) write(prefix string, payload []byte) error {
	if len(payload) == 0 {
		return nil
	}
	s.mu.Lock()
	defer s.mu.Unlock()

	limit := s.maxBytes - s.maxBytes/10
	if prefix == "quarantine_" {
		limit = s.maxBytes / 10
	}
	if err := s.ensureCap(prefix, int64(len(payload)), limit); err != nil {
		return err
	}
	file, err := os.CreateTemp(s.dir, ".pending-")
	if err != nil {
		return err
	}
	temporary := file.Name()
	defer os.Remove(temporary)
	closed := false
	defer func() {
		if !closed {
			file.Close()
		}
	}()
	if _, err := file.Write(payload); err != nil {
		return err
	}
	if err := file.Sync(); err != nil {
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	closed = true
	name := fmt.Sprintf("%s%d_%s.json", prefix, time.Now().UnixNano(), filepath.Base(temporary))
	if err := os.Rename(temporary, filepath.Join(s.dir, name)); err != nil {
		return err
	}
	return s.syncDirectory()
}

func (s *Spool) syncDirectory() error {
	if runtime.GOOS == "windows" {
		return nil
	}
	directory, err := os.Open(s.dir)
	if err != nil {
		return err
	}
	defer directory.Close()
	return directory.Sync()
}

func (s *Spool) files(prefix string) ([]os.DirEntry, int64, error) {
	entries, err := os.ReadDir(s.dir)
	if err != nil {
		return nil, 0, err
	}
	var files []os.DirEntry
	var size int64
	for _, entry := range entries {
		if !strings.HasPrefix(entry.Name(), prefix) || !entry.Type().IsRegular() {
			continue
		}
		info, err := entry.Info()
		if err != nil {
			return nil, 0, err
		}
		files = append(files, entry)
		size += info.Size()
	}
	sort.Slice(files, func(i, j int) bool { return files[i].Name() < files[j].Name() })
	return files, size, nil
}

func (s *Spool) DequeueOldest() (string, []byte, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	files, _, err := s.files("batch_")
	if err != nil {
		return "", nil, err
	}
	if len(files) == 0 {
		return "", nil, errors.New("empty")
	}
	path := filepath.Join(s.dir, files[0].Name())
	file, err := os.Open(path)
	if err != nil {
		return "", nil, err
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return path, nil, err
	}
	if info.Size() > 4*1024*1024 {
		return path, nil, ErrOversizedBatch
	}
	// Defensive bound for files left by an older agent or external corruption.
	data, err := io.ReadAll(io.LimitReader(file, 4*1024*1024+1))
	if len(data) > 4*1024*1024 {
		return path, nil, ErrOversizedBatch
	}
	return path, data, err
}

func (s *Spool) Ack(path string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	root, err := filepath.Abs(s.dir)
	if err != nil {
		return err
	}
	target, err := filepath.Abs(path)
	if err != nil || filepath.Dir(target) != root || !strings.HasPrefix(filepath.Base(target), "batch_") {
		return errors.New("invalid spool acknowledgement path")
	}
	if err := os.Remove(target); err != nil {
		return err
	}
	return s.syncDirectory()
}

func (s *Spool) SizeBytes() int64 {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, pending, _ := s.files("batch_")
	_, quarantined, _ := s.files("quarantine_")
	return pending + quarantined
}

func (s *Spool) Count() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	files, _, _ := s.files("batch_")
	return len(files)
}

func (s *Spool) ensureCap(prefix string, nextSize, limit int64) error {
	// Reject impossible writes before evicting any existing records.
	if nextSize > limit {
		return errors.New("payload exceeds spool partition capacity")
	}
	files, size, err := s.files(prefix)
	if err != nil {
		return err
	}
	remaining := len(files)
	for _, entry := range files {
		if size+nextSize <= limit && remaining < 10000 {
			break
		}
		info, err := entry.Info()
		if err != nil {
			return err
		}
		if err := os.Remove(filepath.Join(s.dir, entry.Name())); err != nil {
			return err
		}
		size -= info.Size()
		remaining--
		log.Printf("spool capacity eviction partition=%s bytes=%d", prefix, info.Size())
	}
	return nil
}
