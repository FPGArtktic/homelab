#!/usr/bin/env bash
# Publishes A records for every service .local name pointing at this host's LAN IP.
# We use single-label names (gitea.local, portainer.local, ...) because Linux
# nss-mdns cannot resolve multi-label .local subdomains (e.g. gitea.homelab.local)
# via getaddrinfo, even though the avahi daemon can. Single-label names resolve
# on every mDNS client with no /etc/hosts workaround.
# Run as a systemd service (see setup-host.sh).
set -euo pipefail

LAN_IF=$(ip route show default | awk '/default/ {print $5; exit}')
IP=$(ip -4 -o addr show "$LAN_IF" | awk '{print $4}' | cut -d/ -f1)

# homelab.local itself is already advertised by avahi (host-name=homelab).
NAMES=(gitea portainer ci logs netdata files archive registry registry-ui)

echo "Publishing *.local -> ${IP} (iface ${LAN_IF})"
pids=()
for n in "${NAMES[@]}"; do
  avahi-publish -a -R "${n}.local" "$IP" &
  pids+=($!)
done

trap 'kill "${pids[@]}" 2>/dev/null' EXIT TERM INT
wait
