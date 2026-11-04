#!/usr/bin/env bash
# Creates local secrets OUTSIDE the repo (never committed). Existing values are kept;
# keys added later to the template are appended to an existing env file.
#   ~/.config/homelab/homelab.env              -> EnvironmentFile for redis, gitlab, forgejo
#   ~/.config/homelab/portainer_admin_password -> Portainer --admin-password-file
set -euo pipefail

DIR="${HOME}/.config/homelab"
ENV_FILE="${DIR}/homelab.env"
PORTAINER_PW="${DIR}/portainer_admin_password"

install -d -m 700 "$DIR"
umask 077

# key=generator pairs. A key missing from an existing file is appended.
declare -A GEN=(
  [REDIS_PASSWORD]=$(openssl rand -hex 24)
  [GITLAB_ROOT_PASSWORD]=$(openssl rand -hex 16)
  [FORGEJO_ADMIN_PASSWORD]=$(openssl rand -hex 16)
  [GF_SECURITY_ADMIN_PASSWORD]=$(openssl rand -hex 16)
)
touch "$ENV_FILE"
for key in REDIS_PASSWORD GITLAB_ROOT_PASSWORD FORGEJO_ADMIN_PASSWORD GF_SECURITY_ADMIN_PASSWORD; do
  if ! grep -q "^${key}=" "$ENV_FILE"; then
    echo "${key}=${GEN[$key]}" >> "$ENV_FILE"
    echo "added ${key} to $ENV_FILE"
  fi
done

if [[ ! -f $PORTAINER_PW ]]; then
  openssl rand -hex 16 > "$PORTAINER_PW"
  echo "created $PORTAINER_PW"
fi
