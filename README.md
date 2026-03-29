# network_monitor
Monitor conntrack and do dns fingerprinting on a router. Go agent. rails webui.





# Run with test file
CONNTRACK_INPUT_FILE=spec/fixtures/conntrack/router_extended.txt rake conntrack:print_outbound


# Run live with 
CONNTRACK_COMMAND="sudo conntrack -L -o extended" bin/rails netmon:ingest_loop
