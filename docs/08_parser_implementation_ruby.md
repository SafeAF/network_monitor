# Conntrack parser implementation (Ruby)

## Goal
Parse `conntrack -L -o extended` output from conntrack-tools v1.4.7 into a normalized struct:

- family: "ipv4" | "ipv6"
- proto: "tcp" | "udp" | ...
- timeout: Integer
- state: String?  (TCP usually has; UDP may omit)
- orig: { src, dst, sport?, dport?, packets?, bytes? }
- reply: { src, dst, sport?, dport?, packets?, bytes? }
- flags: Array[String]  # e.g. ["ASSURED"]
- mark: Integer?
- use: Integer?

We treat the FIRST tuple as ORIGINAL and the SECOND tuple as REPLY.

## Input examples (must be covered by unit tests)

### TCP with state and counters
ipv4     2 tcp      6 7 CLOSE src=10.0.0.24 dst=23.192.208.70 sport=42334 dport=443 packets=9 bytes=1979 src=23.192.208.70 dst=135.131.124.247 sport=443 dport=42334 packets=11 bytes=3219 [ASSURED] mark=0 use=1

### TCP with state but counters may be missing on some entries
ipv4 2 tcp 6 431987 ESTABLISHED src=10.0.0.24 dst=192.82.242.219 sport=60004 dport=443 src=192.82.242.219 dst=135.131.124.247 sport=443 dport=60004 [ASSURED] mark=0 use=1

### UDP without explicit state token
ipv4 2 udp 17 12 src=10.0.0.24 dst=34.111.60.239 sport=54756 dport=443 packets=23 bytes=3538 src=34.111.60.239 dst=135.131.124.247 sport=443 dport=54756 packets=77 bytes=101240 mark=0 use=1

## Parsing strategy (robust to spacing and optional state)

### 1) Tokenize
Split on whitespace: `tokens = line.strip.split(/\s+/)`.

Header:
- family = tokens[0]
- proto  = tokens[2]
- timeout = Integer(tokens[4])

State:
- tokens[5] is either a state (e.g. ESTABLISHED/TIME_WAIT/CLOSE) OR it is a kv token like "src=..."
- Determine `state` by: if tokens[5].include?("=") then state=nil else state=tokens[5]
- Start parsing kv stream at index:
  - kv_start = state ? 6 : 5

### 2) Parse kv stream
Walk tokens[kv_start..] in order.
We need to parse:
- two tuples each with src/dst and optionally sport/dport/packets/bytes
- bracket flags like "[ASSURED]"
- trailing keys mark=, use=, zone= (ignore zone but allow)

Approach:
- Maintain `tuples = [Tuple.new, Tuple.new]`
- Maintain `tuple_idx = 0`
- For each token:
  - if token starts with "[" and ends with "]": push into flags
  - else if token matches /\A(\w+)=(.+)\z/:
      key = $1, val = $2
      if key in {src,dst,sport,dport,packets,bytes}:
          assign into tuples[tuple_idx]
          When we see a "src=" *after* we've already filled tuples[tuple_idx].src and tuples[tuple_idx].dst and tuples[tuple_idx] has at least sport/dport OR we already saw a complete first tuple, advance tuple_idx to 1.
          Simpler rule: advance tuple_idx from 0->1 on the SECOND occurrence of key "src" in the stream.
      else if key == "mark": mark = val.to_i
      else if key == "use":  use = val.to_i
      else ignore (zone, id, etc)
  - else ignore token

Tuple boundary rule (important):
- conntrack v1.4.7 prints original tuple keys, then repeats keys for reply tuple.
- The easiest and most stable split:
  - The first time we encounter "src=", fill orig
  - The second time we encounter "src=", switch to reply and continue filling reply

### 3) Defaults
If packets/bytes missing, set them to 0 (Integer).
Ports may be missing depending on protocol; store nil.

### 4) Validation
Require:
- orig.src and orig.dst
- reply.src and reply.dst (in your NAT setup, they are present)
If missing, return nil (skip line).

## Data structures
Define immutable structs to reduce accidental mutation.

Recommended:
- Conntrack::Entry = Struct.new(:family,:proto,:timeout,:state,:orig,:reply,:flags,:mark,:use, keyword_init: true)
- Conntrack::Tuple = Struct.new(:src,:dst,:sport,:dport,:packets,:bytes, keyword_init: true)

## Tests (RSpec)
Create tests for:
- tcp + state + counters
- tcp + state + no counters => packets/bytes default to 0
- udp no state + counters
- flags + mark/use present
- extra fields like zone= should not break parsing

## Performance notes
- Avoid regex heavy parsing per token; use starts_with? and split('=',2) in the loop.
- Do not allocate many intermediate hashes.
- Parse into local variables, then build structs at the end.
