# Current Interface And Network Model

## Key Rule

Traffic selection is based on IP/subnet semantics, not on interface names alone.

Interfaces matter for:

- metrics display
- router/NFLOG deployment
- labeling and operations

Interfaces do not define the flow model by themselves.

## LAN/WAN Concepts

The system assumes:

- one or more LAN subnets
- a router or host that can observe outbound traffic
- DNS visibility through local `dnsmasq` logging in agent-driven mode

## Outbound Traffic Model

Outbound traffic means:

- source IP is in configured LAN subnets
- destination IP is outside excluded local/private ranges

This applies conceptually whether the source is:

- conntrack snapshots in Rails
- conntrack events in the Go agent

## Interface Usage Today

### Rails app

The Rails app reads system interface counters for display via:

- `/metrics.json`

Configured interfaces can come from:

- request params
- config
- or `/sys/class/net`

### Go agent

The agent config includes:

- `lan_interfaces`
- `wan_interfaces`
- `lan_subnets`

These values help the router-side collection and deployment context, especially NFLOG and local topology assumptions.

## Private/Local Exclusions

The system excludes private/local destinations when determining outbound internet traffic. The exact helper implementation is in code, but the design intent remains:

- RFC1918 internal ranges excluded as internet destinations
- loopback excluded
- link-local excluded

## DNS Visibility

For domain correlation to work well:

- clients should resolve through the observed `dnsmasq`
- the agent must be able to tail the dnsmasq log

If a client uses DoH or bypasses local DNS, the system may still observe the connection but may lack the true requested domain.
