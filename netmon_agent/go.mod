module netmon_agent

go 1.23.0

require (
	github.com/florianl/go-nflog v1.1.0
	github.com/google/gopacket v1.1.19
	github.com/prometheus/client_golang v1.18.0
	github.com/ti-mo/conntrack v0.6.0
	github.com/ti-mo/netfilter v0.5.3
	gopkg.in/yaml.v3 v3.0.1
)

replace github.com/florianl/go-nflog => ./third_party/go-nflog

require (
	github.com/beorn7/perks v1.0.1 // indirect
	github.com/cespare/xxhash/v2 v2.2.0 // indirect
	github.com/google/go-cmp v0.7.0 // indirect
	github.com/josharian/native v1.1.0 // indirect
	github.com/kr/text v0.2.0 // indirect
	github.com/matttproud/golang_protobuf_extensions/v2 v2.0.0 // indirect
	github.com/mdlayher/netlink v1.7.2 // indirect
	github.com/mdlayher/socket v0.5.1 // indirect
	github.com/pkg/errors v0.9.1 // indirect
	github.com/prometheus/client_model v0.5.0 // indirect
	github.com/prometheus/common v0.45.0 // indirect
	github.com/prometheus/procfs v0.12.0 // indirect
	golang.org/x/net v0.39.0 // indirect
	golang.org/x/sync v0.14.0 // indirect
	golang.org/x/sys v0.33.0 // indirect
	google.golang.org/protobuf v1.31.0 // indirect
)
