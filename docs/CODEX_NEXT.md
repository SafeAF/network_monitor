# Codex Next Steps (do in order, no scope creep)

## Step 1: Add parser + tests
Create:
- app/lib/conntrack/parser.rb
- spec/lib/conntrack/parser_spec.rb
- spec/fixtures/conntrack/*.txt

Requirements:
- Parser must parse conntrack-tools v1.4.7 `conntrack -L -o extended` output.
- Must support lines with and without `state` token.
- Must split ORIGINAL vs REPLY tuples using the 2nd occurrence of `src=`.
- Must parse per-tuple counters `packets=` and `bytes=` when present; default to 0 when absent.
- Must parse [FLAGS] like [ASSURED].
- Must parse trailing `mark=` and `use=` fields.
- Must ignore unknown tokens like zone=.

Tests:
- Add fixture lines based on real output from router.
- 3 test cases minimum: tcp w/ state+counters, tcp w/ state no counters, udp no state+counters.
- Parser returns nil for malformed lines (missing orig/src/dst or reply/src/dst).

## Step 2: Add “connection key” helper
Add Conntrack::Key.from_entry(entry) that returns stable 5-tuple key:
  "#{proto}|#{orig.src}|#{orig.sport}|#{orig.dst}|#{orig.dport}"

## Step 3: Implement a snapshot reader service (no DB yet)
Create Conntrack::Snapshot.read that runs:
  `conntrack -L -o extended`
and returns array of parsed Entry objects.

Must:
- run command safely, handle failures
- allow dependency injection for command output in tests

## Step 4: Wire a rake task to print outbound connections (dev tool)
Add rake task:
  rake conntrack:print_outbound
that:
- reads snapshot
- filters outbound per docs (LOCAL_SUBNETS in config/netmon.yml)
- prints top 20 by total bytes

Stop after Step 4.
Do not build UI, DB, or collectors yet.
