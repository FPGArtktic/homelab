#!/usr/bin/env bash
# Host setup for homelab.local (mDNS). Run: sudo ./setup-host.sh
# Arch Linux. Review before running.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then echo "Run with sudo."; exit 1; fi

echo "==> 1. Install avahi + nss-mdns + docker-compose (plugin)"
pacman -S --needed --noconfirm avahi nss-mdns docker-compose

echo "==> 2. Advertise this host as 'homelab' (homelab.local) over mDNS"
# We do not change the system hostname - only the name avahi advertises.
sed -i 's/^#\?host-name=.*/host-name=homelab/' /etc/avahi/avahi-daemon.conf
grep -q '^host-name=homelab' /etc/avahi/avahi-daemon.conf || \
  sed -i '/^\[server\]/a host-name=homelab' /etc/avahi/avahi-daemon.conf
# Enable publishing CNAME aliases (needed for *.homelab.local)
sed -i 's/^#\?publish-aliases=.*/publish-aliases=yes/' /etc/avahi/avahi-daemon.conf 2>/dev/null || true

# Restrict avahi to the LAN interface ONLY. Otherwise it also advertises on
# docker0 / br-* bridges, which makes LAN peers receive an unreachable
# 172.x address AND triggers a name-collision rename (homelab -> homelab-2/-3...).
LAN_IF=$(ip route show default | awk '/default/ {print $5; exit}')
echo "    LAN interface detected: ${LAN_IF}"
if grep -q '^allow-interfaces=' /etc/avahi/avahi-daemon.conf; then
  sed -i "s/^allow-interfaces=.*/allow-interfaces=${LAN_IF}/" /etc/avahi/avahi-daemon.conf
else
  sed -i "/^#allow-interfaces=eth0/a allow-interfaces=${LAN_IF}" /etc/avahi/avahi-daemon.conf
fi

echo "==> 3. Resolve .local via nss-mdns on this host"
if ! grep -q 'mdns' /etc/nsswitch.conf; then
  sed -i 's/^\(hosts:.*\)files myhostname dns/\1files myhostname mdns_minimal [NOTFOUND=return] dns/' /etc/nsswitch.conf
fi
grep '^hosts' /etc/nsswitch.conf

echo "==> 4. Enable and start avahi-daemon"
systemctl enable --now avahi-daemon
systemctl restart avahi-daemon

echo "==> 5. Docker: mark the registry as insecure (push over http)"
DAEMON=/etc/docker/daemon.json
if [[ ! -f $DAEMON ]]; then
  echo '{ "insecure-registries": ["registry.local"] }' > "$DAEMON"
  systemctl restart docker
elif ! grep -q 'registry.local' "$DAEMON"; then
  echo "NOTE: $DAEMON already exists. Add this to 'insecure-registries' manually:"
  echo '  "registry.local"'
  echo "then: systemctl restart docker"
fi

echo "==> 6. Install mDNS service publishing *.local as A records"
# Single-label .local names (gitea.local, ...) so every mDNS client resolves them;
# Linux nss-mdns cannot resolve multi-label .local subdomains via getaddrinfo.
cat > /etc/systemd/system/homelab-mdns.service <<UNIT
[Unit]
Description=Homelab mDNS .local A-record aliases
After=avahi-daemon.service network-online.target
Wants=network-online.target
Requires=avahi-daemon.service

[Service]
ExecStart=$(cd "$(dirname "$0")" && pwd)/mdns-aliases.sh
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now homelab-mdns.service

echo
echo "==> DONE. Test: ping homelab.local  and  avahi-resolve -n gitea.homelab.local"
