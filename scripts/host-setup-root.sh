#!/usr/bin/env bash
# One-time root step for the homelab. Run ON debian-srv, once:
#   sudo ~/homelab/scripts/host-setup-root.sh
# Lets rootless Podman bind port 80, so nginx serves http://*.local with no port.
# Idempotent. It changes one kernel setting (persisted in /etc/sysctl.d) and
# enables linger for the homelab user so services start at boot.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

OWNER="${SUDO_USER:-mokulanis}"
CONF=/etc/sysctl.d/90-unprivileged-ports.conf
WANT='net.ipv4.ip_unprivileged_port_start=80'

if [[ ! -f $CONF ]] || ! grep -qxF "$WANT" "$CONF"; then
  echo "$WANT" > "$CONF"
  echo "wrote $CONF"
fi
sysctl -p "$CONF" >/dev/null
echo "ip_unprivileged_port_start = $(cat /proc/sys/net/ipv4/ip_unprivileged_port_start)"

loginctl enable-linger "$OWNER"
echo "linger($OWNER) = $(loginctl show-user "$OWNER" -p Linger --value)"

# Warn if something other than the homelab already listens on :80.
if ss -tln | grep -q ':80[[:space:]]'; then
  echo "WARNING: something already listens on :80:" >&2
  ss -tlnp | grep ':80[[:space:]]' >&2 || true
fi
echo "done. Next, as $OWNER: ~/homelab/scripts/install.sh"
