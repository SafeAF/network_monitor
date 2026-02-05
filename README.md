# network_monitor
monitor the local network


test conntrack component with bin/rails conntrack:print_outbound after its ready

CONNTRACK_INPUT_FILE=spec/fixtures/conntrack/router_extended.txt rake conntrack:print_outbound
