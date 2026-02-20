# NFLOG Rules

The agent expects NFLOG groups 10 (INPUT drops) and 11 (FORWARD drops).

Apply the example rules:

- `deploy/iptables/netmon-nflog.rules.v4`

Ensure you insert jumps to `NETMON_INPUT_DROPLOG` and `NETMON_FORWARD_DROPLOG`
just before your final drop rules, or directly before explicit DROP rules for
traffic you intend to log.
