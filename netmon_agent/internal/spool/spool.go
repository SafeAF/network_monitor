package spool

import (
  "encoding/json"
  "errors"
  "fmt"
  "os"
  "path/filepath"
  "sort"
  "strings"
  "sync"
  "time"
)

type Spool struct {
  dir     string
  maxBytes int64
  mu      sync.Mutex
}

type Batch struct {
  Payload json.RawMessage
}

func New(dir string, maxBytes int64) *Spool {
  return &Spool{dir: dir, maxBytes: maxBytes}
}

func (s *Spool) Ensure() error {
  return os.MkdirAll(s.dir, 0o755)
}

func (s *Spool) Enqueue(batch []byte) error {
  if len(batch) == 0 {
    return nil
  }
  s.mu.Lock()
  defer s.mu.Unlock()

  if err := s.ensureCap(int64(len(batch))); err != nil {
    return err
  }

  name := fmt.Sprintf("batch_%d.json", time.Now().UnixNano())
  path := filepath.Join(s.dir, name)
  return os.WriteFile(path, batch, 0o600)
}

func (s *Spool) DequeueOldest() (string, []byte, error) {
  s.mu.Lock()
  defer s.mu.Unlock()

  entries, err := os.ReadDir(s.dir)
  if err != nil {
    return "", nil, err
  }
  files := make([]string, 0, len(entries))
  for _, e := range entries {
    if e.IsDir() || !strings.HasPrefix(e.Name(), "batch_") {
      continue
    }
    files = append(files, e.Name())
  }
  if len(files) == 0 {
    return "", nil, errors.New("empty")
  }
  sort.Strings(files)
  oldest := files[0]
  path := filepath.Join(s.dir, oldest)
  data, err := os.ReadFile(path)
  if err != nil {
    return "", nil, err
  }
  return path, data, nil
}

func (s *Spool) Ack(path string) error {
  return os.Remove(path)
}

func (s *Spool) SizeBytes() int64 {
  s.mu.Lock()
  defer s.mu.Unlock()
  entries, err := os.ReadDir(s.dir)
  if err != nil {
    return 0
  }
  var total int64
  for _, e := range entries {
    if e.IsDir() || !strings.HasPrefix(e.Name(), "batch_") {
      continue
    }
    info, err := e.Info()
    if err != nil {
      continue
    }
    total += info.Size()
  }
  return total
}

func (s *Spool) Count() int {
  s.mu.Lock()
  defer s.mu.Unlock()
  entries, err := os.ReadDir(s.dir)
  if err != nil {
    return 0
  }
  count := 0
  for _, e := range entries {
    if e.IsDir() || !strings.HasPrefix(e.Name(), "batch_") {
      continue
    }
    count++
  }
  return count
}

func (s *Spool) ensureCap(nextSize int64) error {
  cur := s.SizeBytes()
  if cur+nextSize <= s.maxBytes {
    return nil
  }
  entries, err := os.ReadDir(s.dir)
  if err != nil {
    return err
  }
  files := make([]string, 0, len(entries))
  for _, e := range entries {
    if e.IsDir() || !strings.HasPrefix(e.Name(), "batch_") {
      continue
    }
    files = append(files, e.Name())
  }
  sort.Strings(files)
  for _, name := range files {
    if cur+nextSize <= s.maxBytes {
      break
    }
    path := filepath.Join(s.dir, name)
    info, err := os.Stat(path)
    if err != nil {
      continue
    }
    if err := os.Remove(path); err != nil {
      continue
    }
    cur -= info.Size()
  }
  if cur+nextSize > s.maxBytes {
    return errors.New("spool full")
  }
  return nil
}
