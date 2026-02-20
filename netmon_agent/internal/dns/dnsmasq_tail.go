package dns

import (
  "bufio"
  "context"
  "io"
  "os"
  "syscall"
  "time"

  "netmon_agent/internal/metrics"
)

func Tail(ctx context.Context, path string, out chan<- string, m *metrics.Metrics) {
  ticker := time.NewTicker(1 * time.Second)
  defer ticker.Stop()

  var file *os.File
  var reader *bufio.Reader
  var inode uint64

  reopen := func() {
    if file != nil {
      _ = file.Close()
    }
    f, err := os.Open(path)
    if err != nil {
      file = nil
      reader = nil
      return
    }
    file = f
    reader = bufio.NewReader(f)
    stat, _ := f.Stat()
    if stat != nil {
      if s, ok := stat.Sys().(*syscall.Stat_t); ok {
        inode = s.Ino
      }
    }
    _, _ = f.Seek(0, io.SeekEnd)
  }

  reopen()

  for {
    select {
    case <-ctx.Done():
      if file != nil {
        _ = file.Close()
      }
      return
    case <-ticker.C:
      if file == nil {
        reopen()
        continue
      }
      stat, err := file.Stat()
      if err == nil {
        if s, ok := stat.Sys().(*syscall.Stat_t); ok {
          if s.Ino != inode {
            reopen()
          }
        }
      }
      for {
        line, err := reader.ReadString('\n')
        if err != nil {
          break
        }
        select {
        case out <- line:
        default:
          if m != nil {
            m.DroppedLocalTotal.WithLabelValues("dns_lines").Inc()
          }
        }
      }
    }
  }
}
