package dns

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

const sampleQuery = "Nov 12 12:00:00 dnsmasq[1]: query[A] example.com from 10.0.0.20\n"
const sampleReply = "Nov 12 12:00:00 dnsmasq[1]: reply example.com is 203.0.113.8\n"

func writeLog(t *testing.T, path, text string, appendMode bool) {
	t.Helper()
	flags := os.O_CREATE | os.O_WRONLY | os.O_TRUNC
	if appendMode {
		flags = os.O_CREATE | os.O_WRONLY | os.O_APPEND
	}
	file, err := os.OpenFile(path, flags, 0o600)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := file.WriteString(text); err != nil {
		file.Close()
		t.Fatal(err)
	}
	if err := file.Close(); err != nil {
		t.Fatal(err)
	}
}

func pollLines(t *testing.T, tail *logTail) []string {
	t.Helper()
	var lines []string
	if err := tail.poll(context.Background(), func(line string) { lines = append(lines, line) }); err != nil {
		t.Fatal(err)
	}
	return lines
}

func TestTailStartsAtEndAndPreservesPartialWrites(t *testing.T) {
	path := filepath.Join(t.TempDir(), "dnsmasq.log")
	writeLog(t, path, sampleQuery, false)
	tail := newLogTail(path, nil)
	defer tail.close()
	if len(pollLines(t, tail)) != 0 {
		t.Fatal("replayed pre-start history")
	}
	cut := len(sampleReply) / 2
	writeLog(t, path, sampleReply[:cut], true)
	if len(pollLines(t, tail)) != 0 {
		t.Fatal("emitted an incomplete line")
	}
	writeLog(t, path, sampleReply[cut:], true)
	if got := pollLines(t, tail); !reflect.DeepEqual(got, []string{sampleReply}) {
		t.Fatalf("fragment lost or duplicated: %#v", got)
	}
}

func TestTailRenameDrainsOldFileThenReadsReplacementFromStart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "dnsmasq.log")
	writeLog(t, path, sampleQuery, false)
	tail := newLogTail(path, nil)
	defer tail.close()
	pollLines(t, tail)
	writeLog(t, path, sampleReply, true)
	if err := os.Rename(path, path+".1"); err != nil {
		t.Fatal(err)
	}
	writeLog(t, path, sampleQuery, false)
	if got := pollLines(t, tail); !reflect.DeepEqual(got, []string{sampleReply, sampleQuery}) {
		t.Fatalf("rotation lost lines: %#v", got)
	}
	if len(pollLines(t, tail)) != 0 {
		t.Fatal("rotation replayed lines twice")
	}
}

func TestTailKeepsOldDescriptorAcrossRenameCreateGap(t *testing.T) {
	path := filepath.Join(t.TempDir(), "dnsmasq.log")
	writeLog(t, path, "", false)
	tail := newLogTail(path, nil)
	defer tail.close()
	pollLines(t, tail)
	if err := os.Rename(path, path+".1"); err != nil {
		t.Fatal(err)
	}
	writeLog(t, path+".1", sampleReply, true)
	var got []string
	err := tail.poll(context.Background(), func(line string) { got = append(got, line) })
	if !os.IsNotExist(err) || !reflect.DeepEqual(got, []string{sampleReply}) {
		t.Fatalf("old descriptor was not drained: %#v, %v", got, err)
	}
	writeLog(t, path, sampleQuery, false)
	if got := pollLines(t, tail); !reflect.DeepEqual(got, []string{sampleQuery}) {
		t.Fatal("missed replacement contents")
	}
}

func TestTailMissingAtStartupReadsCreatedFileFromStart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "dnsmasq.log")
	tail := newLogTail(path, nil)
	defer tail.close()
	if err := tail.poll(context.Background(), func(string) {}); !os.IsNotExist(err) {
		t.Fatal(err)
	}
	writeLog(t, path, sampleQuery, false)
	if got := pollLines(t, tail); !reflect.DeepEqual(got, []string{sampleQuery}) {
		t.Fatal("skipped data while waiting for log creation")
	}
}

func TestTailFollowsCopytruncateAndFastRegrowth(t *testing.T) {
	for _, initial := range []string{strings.Repeat(sampleQuery, 4), "old\n"} {
		path := filepath.Join(t.TempDir(), "dnsmasq.log")
		writeLog(t, path, initial, false)
		tail := newLogTail(path, nil)
		pollLines(t, tail)
		writeLog(t, path, sampleReply, false)
		got := pollLines(t, tail)
		tail.close()
		if !reflect.DeepEqual(got, []string{sampleReply}) {
			t.Fatalf("copytruncate/regrowth missed data: %#v", got)
		}
	}
}

func TestTailDoesNotJoinFragmentsAcrossRotations(t *testing.T) {
	path := filepath.Join(t.TempDir(), "dnsmasq.log")
	writeLog(t, path, "", false)
	tail := newLogTail(path, nil)
	defer tail.close()
	pollLines(t, tail)
	writeLog(t, path, "old incomplete", true)
	pollLines(t, tail)
	if err := os.Rename(path, path+".1"); err != nil {
		t.Fatal(err)
	}
	writeLog(t, path, sampleQuery, false)
	if got := pollLines(t, tail); !reflect.DeepEqual(got, []string{sampleQuery}) {
		t.Fatal("joined data from different log files")
	}
}

func TestTailDiscardsSuffixOfPreStartupPartialLine(t *testing.T) {
	path := filepath.Join(t.TempDir(), "dnsmasq.log")
	writeLog(t, path, "old incomplete", false)
	tail := newLogTail(path, nil)
	defer tail.close()
	pollLines(t, tail)
	writeLog(t, path, " suffix\n"+sampleQuery, true)
	if got := pollLines(t, tail); !reflect.DeepEqual(got, []string{sampleQuery}) {
		t.Fatal("treated a partial history suffix as a new line")
	}
}

func TestTailDropsOversizedLinesAndRecoversAtNextDelimiter(t *testing.T) {
	path := filepath.Join(t.TempDir(), "dnsmasq.log")
	writeLog(t, path, "", false)
	tail := newLogTail(path, nil)
	defer tail.close()
	pollLines(t, tail)
	writeLog(t, path, strings.Repeat("x", maxDNSLogLine+1)+"\n"+sampleQuery, true)
	if got := pollLines(t, tail); !reflect.DeepEqual(got, []string{sampleQuery}) {
		t.Fatal("oversized line was emitted or blocked following lines")
	}
	if len(tail.partial) > maxDNSLogLine {
		t.Fatal("unbounded partial-line allocation")
	}
}

func TestTailBoundsWorkPerPollAndChecksCancellation(t *testing.T) {
	path := filepath.Join(t.TempDir(), "dnsmasq.log")
	writeLog(t, path, "", false)
	tail := newLogTail(path, nil)
	defer tail.close()
	pollLines(t, tail)
	writeLog(t, path, strings.Repeat("x", 3*maxTailReadPerPoll), true)
	if len(pollLines(t, tail)) != 0 || tail.offset > maxTailReadPerPoll+4096 || len(tail.partial) > maxDNSLogLine {
		t.Fatal("tail exceeded per-poll bounds")
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if err := tail.poll(ctx, func(string) { t.Fatal("emitted after cancellation") }); !errors.Is(err, context.Canceled) {
		t.Fatal(err)
	}
}

func TestTailRejectsNonRegularPaths(t *testing.T) {
	tail := newLogTail(t.TempDir(), nil)
	defer tail.close()
	if err := tail.poll(context.Background(), func(string) {}); err == nil {
		t.Fatal("accepted a directory as a log file")
	}
}
