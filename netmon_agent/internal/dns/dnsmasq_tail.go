package dns

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"io"
	"log"
	"os"
	"time"

	"netmon_agent/internal/metrics"
)

const (
	maxDNSLogLine       = 16 * 1024
	maxTailReadPerPoll  = 1024 * 1024
	tailCheckpointBytes = 64
)

type logTail struct {
	path         string
	file         *os.File
	reader       *bufio.Reader
	offset       int64
	checkpoint   []byte
	partial      []byte
	discarding   bool
	firstAttempt bool
	metrics      *metrics.Metrics
}

func newLogTail(path string, m *metrics.Metrics) *logTail {
	return &logTail{path: path, firstAttempt: true, metrics: m}
}

func (t *logTail) close() {
	if t.file != nil {
		t.file.Close()
	}
	t.file, t.reader = nil, nil
}

func (t *logTail) open(atEnd bool) error {
	info, err := os.Stat(t.path)
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() {
		return errors.New("dns log must be a regular file")
	}
	file, err := os.Open(t.path)
	if err != nil {
		return err
	}
	info, err = file.Stat()
	if err != nil || !info.Mode().IsRegular() {
		file.Close()
		if err != nil {
			return err
		}
		return errors.New("dns log must be a regular file")
	}
	offset := int64(0)
	if atEnd {
		offset = info.Size()
	}
	if _, err := file.Seek(offset, io.SeekStart); err != nil {
		file.Close()
		return err
	}
	t.close()
	t.file, t.reader, t.offset = file, bufio.NewReader(file), offset
	t.partial, t.checkpoint, t.discarding = nil, nil, false
	if offset > 0 {
		size := min(int64(tailCheckpointBytes), offset)
		t.checkpoint = make([]byte, size)
		if _, err := file.ReadAt(t.checkpoint, offset-size); err != nil {
			t.close()
			return err
		}
		if t.checkpoint[len(t.checkpoint)-1] != '\n' {
			t.discarding = true
			t.drop("dns_partial_lines")
		}
	}
	return nil
}

func (t *logTail) drop(stream string) {
	if t.metrics != nil {
		t.metrics.DroppedLocalTotal.WithLabelValues(stream).Inc()
	}
}

func (t *logTail) rotation(reason string) {
	if t.metrics != nil {
		t.metrics.DNSLogRotations.WithLabelValues(reason).Inc()
	}
}

func (t *logTail) reset() error {
	if len(t.partial) > 0 || t.discarding {
		t.drop("dns_partial_lines")
	}
	if _, err := t.file.Seek(0, io.SeekStart); err != nil {
		return err
	}
	t.reader.Reset(t.file)
	t.offset, t.partial, t.checkpoint, t.discarding = 0, nil, nil, false
	t.rotation("truncate")
	return nil
}

// poll is deterministic so rotation/fragment behavior can be tested without
// sleeping. The first attempt skips existing history; later opens start at 0.
func (t *logTail) poll(ctx context.Context, emit func(string)) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	if t.file == nil {
		atEnd := t.firstAttempt
		t.firstAttempt = false
		if err := t.open(atEnd); err != nil {
			return err
		}
	}
	openInfo, err := t.file.Stat()
	if err != nil {
		return err
	}
	pathInfo, pathErr := os.Stat(t.path)
	if pathErr == nil && !os.SameFile(openInfo, pathInfo) {
		// Drain complete old-file lines before switching. If that old file has
		// a large backlog, finish it in bounded polls instead of starving work.
		atEOF, err := t.drain(ctx, emit)
		if err != nil {
			return err
		}
		if !atEOF {
			return nil
		}
		partialLost := len(t.partial) > 0 || t.discarding
		if err := t.open(false); err != nil {
			return err
		}
		if partialLost {
			t.drop("dns_partial_lines")
		}
		t.rotation("replace")
	} else {
		truncated := openInfo.Size() < t.offset
		if !truncated && len(t.checkpoint) > 0 {
			probe := make([]byte, len(t.checkpoint))
			n, err := t.file.ReadAt(probe, t.offset-int64(len(probe)))
			truncated = (err == io.EOF || (err == nil && n != len(probe))) || (err == nil && !bytes.Equal(probe, t.checkpoint))
			if err != nil && err != io.EOF {
				return err
			}
		}
		if truncated {
			if err := t.reset(); err != nil {
				return err
			}
		}
	}
	_, err = t.drain(ctx, emit)
	if err != nil {
		return err
	}
	// A missing path may just be the rename/create gap. Keep reading the old
	// descriptor while surfacing the missing replacement to monitoring.
	return pathErr
}

func (t *logTail) drain(ctx context.Context, emit func(string)) (bool, error) {
	read := 0
	for read < maxTailReadPerPoll {
		if err := ctx.Err(); err != nil {
			return false, err
		}
		fragment, err := t.reader.ReadSlice('\n')
		read += len(fragment)
		t.offset += int64(len(fragment))
		if len(fragment) > 0 {
			t.checkpoint = append(t.checkpoint, fragment...)
			if len(t.checkpoint) > tailCheckpointBytes {
				t.checkpoint = append([]byte(nil), t.checkpoint[len(t.checkpoint)-tailCheckpointBytes:]...)
			}
			if !t.discarding {
				if len(t.partial)+len(fragment) > maxDNSLogLine {
					t.partial, t.discarding = nil, true
					t.drop("dns_oversized_lines")
				} else {
					t.partial = append(t.partial, fragment...)
				}
			}
			if fragment[len(fragment)-1] == '\n' {
				if !t.discarding {
					emit(string(t.partial))
				}
				t.partial, t.discarding = nil, false
				if t.metrics != nil {
					t.metrics.DNSTailLastRead.Set(float64(time.Now().Unix()))
				}
			}
		}
		switch err {
		case nil, bufio.ErrBufferFull:
		case io.EOF:
			return true, nil
		default:
			return false, err
		}
	}
	return false, nil
}

func Tail(ctx context.Context, path string, out chan<- string, m *metrics.Metrics) {
	tail := newLogTail(path, m)
	defer tail.close()
	emit := func(line string) {
		if ctx.Err() != nil {
			return
		}
		select {
		case out <- line:
		default:
			tail.drop("dns_lines")
		}
	}
	lastError := ""
	poll := func() {
		err := tail.poll(ctx, emit)
		if err != nil && ctx.Err() == nil {
			if m != nil {
				m.DNSTailReadErrors.Inc()
			}
			if err.Error() != lastError {
				log.Printf("dns log tail error: %v", err)
				lastError = err.Error()
			}
		} else if err == nil {
			lastError = ""
		}
	}
	poll()
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			poll()
		}
	}
}
