# Homelab

Docker Compose stack with an nginx reverse proxy and mDNS. Every service has its own
single-label `.local` name, reachable from any mDNS client (macOS, iOS, Windows 10+,
Linux with avahi) **without touching `/etc/hosts`**.

## Services

| URL                        | What it is                     |
|----------------------------|--------------------------------|
| http://homelab.local       | **Homepage** – start dashboard |
| http://portainer.local     | Portainer – Docker management  |
| http://logs.local          | Dozzle – container logs        |
| http://netdata.local       | Netdata – host monitoring      |
| http://gitea.local         | Gitea – git repos (SSH :2222)  |
| http://ci.local            | Woodpecker CI                  |
| http://files.local         | File Browser                   |
| http://archive.local       | ArchiveBox                     |
| http://registry.local      | Docker Registry (API v2)       |
| http://registry-ui.local   | Registry UI                    |
| redis:6379 / host :6379    | Redis (password in `.env`)     |

## Getting started

```bash
cd ~/homelab

# 1. Host setup: avahi + mDNS + docker-compose + insecure registry + mDNS service
sudo ./setup-host.sh

# 2. Start the whole stack
docker compose up -d

# 3. Inspect
docker compose ps
docker compose logs -f nginx
```

nginx routes each `*.local` (server_name) to the right container. The names are
advertised on the LAN by the `homelab-mdns` systemd service, which publishes an A record
per name -> this host's LAN IP (installed by `setup-host.sh`). `homelab.local` is the
host's own avahi hostname.

## First-run configuration

### Gitea
1. Open http://gitea.local and finish the installer (SQLite DB is preconfigured).
2. Create an account – **the first user becomes the admin**. Put that login into `.env`
   as `WOODPECKER_ADMIN` if it differs from `admin`.

### Woodpecker CI (OAuth to Gitea) – step 5
1. In Gitea: **Settings → Applications → Create new OAuth2 application**.
   - Name: `Woodpecker`
   - Redirect URI: `http://ci.local/authorize`
2. Copy the **Client ID** and **Client Secret** into `.env`:
   ```
   WOODPECKER_GITEA_CLIENT=...
   WOODPECKER_GITEA_SECRET=...
   ```
3. Reload: `docker compose up -d woodpecker-server woodpecker-agent`
4. Open http://ci.local and log in via Gitea.

### File Browser
Default login `admin` / `admin` – change the password on first login.

### Docker Registry – pushing images
`setup-host.sh` adds `registry.local` to `insecure-registries` (push over HTTP). Test:
```bash
docker pull alpine
docker tag alpine registry.local/alpine:test
docker push registry.local/alpine:test
```

## Accessing from another machine on the LAN

Single-label `.local` names resolve on any mDNS client:
- **macOS / iOS / Windows 10+** – works out of the box.
- **Linux client** – install a resolver once, then everything resolves via mDNS:
  ```bash
  sudo pacman -S --needed avahi nss-mdns          # (Arch)
  sudo systemctl enable --now avahi-daemon
  # mdns4_minimal is enough for single-label .local names, and IPv4-only:
  sudo sed -i 's/^hosts:.*/hosts: mymachines mdns4_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] files myhostname dns/' /etc/nsswitch.conf
  getent ahostsv4 gitea.local     # -> <server LAN IP>
  ```

Why single-label: Linux nss-mdns **cannot** resolve multi-label `.local` subdomains
(`gitea.homelab.local`) via getaddrinfo — the NSS module rejects them even though the
avahi daemon resolves them. Single-label names sidestep that entirely.

Tip: if a browser fails while `curl` works, it's browser DNS cache or "Secure DNS/DoH" —
restart the browser or disable DoH.

## Notes

- Reverse proxy: **nginx** (`nginx/conf.d/*.conf`, one server block per service).
- **No HTTPS** – intentional, for simplicity on the LAN. HTTP only on port 80.
- Secrets (`REDIS_PASSWORD`, `WOODPECKER_AGENT_SECRET`) live in `.env` – change if you like.
- Persistent data: named volumes (databases) + `./data/` (files, archivebox, registry).
- Stop: `docker compose down` (data kept). Full reset: `docker compose down -v`.
- mDNS names: `systemctl status homelab-mdns` (host service running `mdns-aliases.sh`).
- Set a DHCP reservation for this host so its LAN IP stays fixed.
