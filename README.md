# Homelab

Rootless Podman stack (Quadlet + systemd user units) on a Debian host, behind an
nginx reverse proxy and mDNS. Every service has a single-label `.local` name,
reachable from any mDNS client (macOS, iOS, Windows 10+, Linux with avahi) **without
touching `/etc/hosts`**. Git, CI/CD and the container registry are one GitLab.

Host: `mokulanis@192.168.101.253` (debian-srv). Everything runs as the normal user.

## Services

All web UIs are on plain **port 80** through the homelab nginx.

| URL                              | What it is                          |
|----------------------------------|-------------------------------------|
| http://homelab.local             | **Homepage** - start dashboard      |
| http://gitlab.local              | **GitLab** - repos, CI/CD           |
| ssh://git@gitlab.local:2222      | GitLab SSH (git clone/push)         |
| gitlab.local:5050                | GitLab container registry           |
| http://portainer.local           | Portainer - container management    |
| http://logs.local                | Dozzle - container logs             |
| http://netdata.local             | Netdata - host monitoring           |
| http://files.local               | File Browser                        |
| http://archive.local             | ArchiveBox                          |
| redis:6379 (internal only)       | Redis, password in `homelab.env`    |

## Layout

```
quadlet/          -> ~/.config/containers/systemd/   (one unit per container + network)
systemd/          -> ~/.config/systemd/user/         (homelab-mdns.service)
scripts/install.sh   installs everything, enables autostart, restarts what changed
scripts/gen-env.sh   creates secrets in ~/.config/homelab/ (never in git)
nginx/            reverse proxy config (one server block per name)
homepage/         dashboard config
gitlab/gitlab.rb  GitLab Omnibus config (mounted read-only)
mdns-aliases.sh   publishes the *.local names via avahi
data/             bind-mounted state (gitignored)
```

## One-time host setup (needs root, once)

Rootless Podman cannot bind ports below 1024, and nginx serves :80. Allow it once:

```bash
echo 'net.ipv4.ip_unprivileged_port_start=80' | sudo tee /etc/sysctl.d/90-unprivileged-ports.conf
sudo sysctl --system
```

This lets any local user bind ports 80 and up. On a single-user host that is fine.
Autostart also needs linger; `install.sh` enables it, or run once:
`sudo loginctl enable-linger mokulanis`.

## Install / update on the server

From the repo checkout:

```bash
rsync -az --exclude data/ --exclude .git/ ./ mokulanis@192.168.101.253:homelab/
ssh mokulanis@192.168.101.253 'cd homelab && ./scripts/install.sh'
```

`install.sh` is idempotent. It creates secrets on first run, copies the units, and
restarts only the services whose files changed. GitLab restarts only when `gitlab.rb`
changes, because it is slow to boot.

### First-time GitLab setup

1. Wait for the first start (several minutes, database migrations):
   `systemctl --user status gitlab`.
2. Log in at http://gitlab.local as `root`. The password is `GITLAB_ROOT_PASSWORD`
   in `~/.config/homelab/homelab.env`. Change it after the first login.
3. Register the runner. In GitLab create a new runner (group or instance) and copy its
   token (`glrt-...`), then on the server:

   ```bash
   podman exec -it gitlab-runner gitlab-runner register --non-interactive \
     --url http://gitlab.local --token glrt-XXXX \
     --executor docker --docker-image alpine:3.20 \
     --docker-network-mode homelab \
     --docker-extra-hosts gitlab.local:10.90.0.20 \
     --docker-volumes /cache
   ```

   Job containers join the `homelab` network and reach GitLab at the fixed IP
   `10.90.0.20`.
4. Add the CI/CD variable `DEPLOY_SSH_KEY` (masked): a private key that can SSH to
   `mokulanis@192.168.101.253`. The `deploy` job is manual on the default branch.

## Using it from other LAN machines

Single-label `.local` names resolve on any mDNS client:
- **macOS / iOS / Windows 10+**: works out of the box.
- **Linux**: install a resolver once, then names resolve via mDNS:
  ```bash
  sudo pacman -S --needed avahi nss-mdns          # (Arch)
  sudo systemctl enable --now avahi-daemon
  sudo sed -i 's/^hosts:.*/hosts: mymachines mdns4_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] files myhostname dns/' /etc/nsswitch.conf
  getent ahostsv4 gitlab.local                    # -> 192.168.101.253
  ```

Single-label names are used on purpose: Linux nss-mdns cannot resolve multi-label
`.local` subdomains (`gitlab.homelab.local`) via getaddrinfo.

If a browser fails while `curl` works, restart it or disable Secure DNS/DoH.

### Pushing images to the GitLab registry

The registry is plain HTTP, so mark it insecure on each client:

```toml
# /etc/containers/registries.conf.d/homelab.conf   (podman / buildah)
[[registry]]
location = "gitlab.local:5050"
insecure = true
```

Docker clients use `"insecure-registries": ["gitlab.local:5050"]` in `daemon.json`.

## Operations

```bash
systemctl --user list-units 'homelab*' nginx.service gitlab.service   # status
systemctl --user --failed                                             # anything broken?
systemctl --user restart gitlab                                       # one service
journalctl --user -u gitlab -f                                        # logs
podman ps                                                             # containers
```

**Updates are manual.** Pull the new image (`podman pull <image>`), update the tag in
the quadlet if you pinned it, run `install.sh`, then restart the service.

**Backups:**
- Named volumes (GitLab, Portainer, Redis, Netdata): `podman volume export <name> > <name>.tar`.
- `~/homelab/data/` (files, ArchiveBox, File Browser DB).
- `~/.config/homelab/` (secrets). Keep this out of git.

## Notes

- Reverse proxy: **nginx** on :80, HTTP only. No HTTPS, intentional for the LAN.
- Redis is internal only. Nothing is published on host :6379.
- ArchiveBox is public (`PUBLIC_INDEX`/`PUBLIC_SNAPSHOTS`). File Browser's default login
  is `admin` / `admin`, so change it on first login. The File Browser project is
  archived upstream and no longer gets security fixes.
- Netdata runs rootless, so its host metrics are limited compared to a rootful setup.
- The Docker-based stack (compose, Gitea, Woodpecker, Docker registry) was removed.
  Old commits still contain its example secrets, so those values are public and must not
  be reused.
- DHCP reservation for `192.168.101.253` is recommended. The dashboard's allowed hosts
  include that IP.
