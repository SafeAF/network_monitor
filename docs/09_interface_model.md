# Interface model (important)

## Key rule
Conntrack entries are NOT per-interface.
Do not filter conntrack data by interface.

## Selection logic
Connections are selected using IP semantics only.

Outbound connection definition:
- orig.src_ip ∈ LOCAL_SUBNETS
- orig.dst_ip ∉ PRIVATE_RANGES
- proto any

This logic works:
- on routers
- on workstations
- in dev and prod
- regardless of interface names

## LOCAL_SUBNETS
Configurable list, default:
- 10.0.0.0/24

In dev, this includes the workstation IP (e.g. 10.0.0.20).

## PRIVATE_RANGES (exclude)
- 10.0.0.0/8
- 172.16.0.0/12
- 192.168.0.0/16
- 127.0.0.0/8
- 169.254.0.0/16

## Interface usage
Interfaces are used ONLY for:
- displaying RX/TX statistics
- UI binding / security
- optional labeling

Interfaces MUST NOT be used to select or filter conntrack entries.
