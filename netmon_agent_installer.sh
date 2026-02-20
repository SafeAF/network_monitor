#!/usr/bin/env bash
set -euo pipefail

# netmon_agent router installer (Debian, systemd)
# - installs binary to /usr/local/bin/netmon-agent
# - installs config to /etc/netmon-agent/config.yaml (from example if missing)
# - installs systemd unit
# - installs logrotate policy for dnsmasq log + agent log (optional)
# - starts/enables the service
#
# Does NOT apply iptables rules. You will do that yourself.

APP="netmon-agent"
BIN_DST="/usr/local/bin/${APP}"
ETC_DIR="/etc/netmon-agent"
VAR_DIR="/var/lib/netmon-agent"
SPOOL_DIR="${VAR_DIR}/spool"
LOG_DIR="/var/log/netmon-agent"
UNIT_DST="/etc/systemd/system/${APP}.service"
LOGROTATE_DST="/etc/logrotate.d/netmon"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

say() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "run as root"
  fi
}

detect_arch() {
  local m
  m="$(uname -m)"
  case "$m" in
    i386|i486|i586|i686) echo "386" ;;
    x86_64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l|armv6l) echo "arm" ;;
    *) die "unsupported arch: ${m}" ;;
  esac
}

install_dirs() {
  say "Creating directories"
  mkdir -p "${ETC_DIR}" "${SPOOL_DIR}" "${LOG_DIR}"
  chmod 0755 "${ETC_DIR}" "${VAR_DIR}" "${SPOOL_DIR}" "${LOG_DIR}" || true
}

install_config() {
  local cfg="${ETC_DIR}/config.yaml"
  local example="${REPO_ROOT}/deploy/config/config.yaml.example"

  if [[ -f "${cfg}" ]]; then
    say "Config exists: ${cfg} (leaving as-is)"
    return
  fi

  [[ -f "${example}" ]] || die "missing example config: ${example}"

  say "Installing config: ${cfg}"
  cp -a "${example}" "${cfg}"
  chmod 0640 "${cfg}"

  cat <<'EOF'

IMPORTANT: edit /etc/netmon-agent/config.yaml now.
At minimum set:
- router_id
- rails_base_url (LAN URL of your netmon server)
- auth_token (must match Rails)
EOF
}

install_binary() {
  local arch="$1"
  local prebuilt="${REPO_ROOT}/deploy/bin/netmon-agent_linux_${arch}"
  local cmdpkg="${REPO_ROOT}/cmd/netmon_agent"
  local have_go=0

  if command -v go >/dev/null 2>&1; then
    have_go=1
  fi

  if [[ -f "${prebuilt}" ]]; then
    say "Installing prebuilt binary: ${prebuilt} -> ${BIN_DST}"
    install -m 0755 "${prebuilt}" "${BIN_DST}"
    return
  fi

  if [[ "${have_go}" -eq 1 ]]; then
    say "No prebuilt binary found; building locally with Go"
    ( cd "${REPO_ROOT}" && GOOS=linux GOARCH="${arch}" CGO_ENABLED=0 go build -o /tmp/${APP} "${cmdpkg}" )
    install -m 0755 "/tmp/${APP}" "${BIN_DST}"
    rm -f "/tmp/${APP}"
    return
  fi

  die "No prebuilt binary at ${prebuilt} and Go not installed. Either:
  - put a prebuilt binary at ${prebuilt}, or
  - install golang on the router and re-run."
}

install_unit() {
  local src="${REPO_ROOT}/deploy/systemd/netmon-agent.service"
  [[ -f "${src}" ]] || die "missing unit file: ${src}"

  say "Installing systemd unit: ${UNIT_DST}"
  install -m 0644 "${src}" "${UNIT_DST}"
  systemctl daemon-reload
}

install_logrotate() {
  local src="${REPO_ROOT}/deploy/logrotate/netmon"
  if [[ ! -f "${src}" ]]; then
    say "No logrotate config found (skipping)"
    return
  fi
  say "Installing logrotate config: ${LOGROTATE_DST}"
  install -m 0644 "${src}" "${LOGROTATE_DST}"
}

start_service() {
  say "Enabling + starting ${APP}"
  systemctl enable --now "${APP}.service"
}

post_instructions() {
  cat <<'EOF'

NEXT STEPS (you do these manually):

1) Edit config:
   vi /etc/netmon-agent/config.yaml

2) Apply iptables NFLOG rules (your call where/how):
   See: netmon_agent/deploy/iptables/netmon-nflog.rules.v4

3) Verify service:
   systemctl status netmon-agent --no-pager
   journalctl -u netmon-agent -f

4) Verify metrics:
   curl -s http://127.0.0.1:9109/metrics | head

5) Verify Rails ingest endpoint from router:
   curl -sS -H "Authorization: Bearer <token>" \
     -H "Content-Type: application/json" \
     -d '{"router_id":"router-01","sent_at":"2026-02-20T00:00:00Z","events":[]}' \
     http://<server-lan-ip>:3000/api/v1/netmon/events/batch

EOF
}

main() {
  need_root
  say "Detecting architecture"
  local arch
  arch="$(detect_arch)"
  say "Arch: GOARCH=${arch}"

  install_dirs
  install_config
  install_binary "${arch}"
  install_unit
  install_logrotate
  start_service
  post_instructions

  say "Done."
}

main "$@"