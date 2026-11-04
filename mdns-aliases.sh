#!/usr/bin/env bash
# Publishes A records for every service .local name pointing at this host's LAN IP.
# We use single-label names (gitlab.local, portainer.local, ...) because Linux
# nss-mdns cannot resolve multi-label .local subdomains (e.g. gitlab.homelab.local)
# via getaddrinfo, even though the avahi daemon can. Single-label names resolve
# on every mDNS client with no /etc/hosts workaround.
# Run as a user systemd service (systemd/homelab-mdns.service).
set -euo pipefail

# Wait for the LAN to have a routable IPv4 before publishing. At boot this service
# can start before the interface is configured; without this the script would exit
# on an empty IP and rely on systemd's restart loop to eventually succeed.
LAN_IF="" IP=""
for _ in $(seq 1 60); do
  LAN_IF=$(ip route show default | awk '/default/ {print $5; exit}')
  [[ -n $LAN_IF ]] && IP=$(ip -4 -o addr show "$LAN_IF" | awk '{print $4}' | cut -d/ -f1)
  [[ -n $IP ]] && break
  sleep 1
done
if [[ -z $IP ]]; then
  echo "No routable IPv4 after 60s; giving up (systemd will restart)." >&2
  exit 1
fi

# We also publish "homelab" explicitly instead of relying on avahi advertising the
# host's own hostname: on name collision avahi renames the host (homelab-2.local,
# homelab-3.local, ...), which silently breaks homelab.local. An explicit A record
# is immune to that.
NAMES=(homelab info gitlab forgejo grafana microdash mattermost portainer logs netdata files archive)

echo "Publishing *.local -> ${IP} (iface ${LAN_IF})"
pids=()
for n in "${NAMES[@]}"; do
  avahi-publish -a -R "${n}.local" "$IP" &
  pids+=($!)
done

trap 'kill "${pids[@]}" 2>/dev/null' EXIT TERM INT
wait
