# network_monitor
monitor the local network


test conntrack component with bin/rails conntrack:print_outbound after its ready

# Run with test file
CONNTRACK_INPUT_FILE=spec/fixtures/conntrack/router_extended.txt rake conntrack:print_outbound


# Run live with 
CONNTRACK_COMMAND="sudo conntrack -L -o extended" bin/rails netmon:ingest_loop
