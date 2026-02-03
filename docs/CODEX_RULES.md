# Codex rules

- Do not invent dependencies without listing them in Gemfile / package.json.
- Prefer standard library reads (/proc, /sys) for metrics.
- Conntrack ingestion must work with conntrack-tools.
- Outbound connections are determined by original src_ip in 10.0.0.0/24.
- UI must remain fast with ~thousands of conntrack entries.
- All parsing code must have unit tests with sample conntrack output lines.
