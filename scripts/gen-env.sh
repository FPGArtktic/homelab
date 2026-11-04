#!/usr/bin/env bash
# Creates local secrets OUTSIDE the repo (never committed). Existing values are kept;
# keys added later to the template are appended to an existing env file.
#   ~/.config/homelab/homelab.env              -> EnvironmentFile for redis, gitlab, forgejo,
#                                                 grafana, mattermost (+ its DB), gitlab-relay
#   ~/.config/homelab/portainer_admin_password -> Portainer --admin-password-file
set -euo pipefail

DIR="${HOME}/.config/homelab"
ENV_FILE="${DIR}/homelab.env"
PORTAINER_PW="${DIR}/portainer_admin_password"

install -d -m 700 "$DIR"
umask 077
touch "$ENV_FILE"

# Append KEY=VALUE only if KEY is missing, so existing secrets never change.
add_missing() {
  local key=$1 value=$2
  if ! grep -q "^${key}=" "$ENV_FILE"; then
    echo "${key}=${value}" >> "$ENV_FILE"
    echo "added ${key} to $ENV_FILE"
  fi
}
get() { grep "^$1=" "$ENV_FILE" | cut -d= -f2-; }

add_missing REDIS_PASSWORD "$(openssl rand -hex 24)"
add_missing GITLAB_ROOT_PASSWORD "$(openssl rand -hex 16)"
add_missing FORGEJO_ADMIN_PASSWORD "$(openssl rand -hex 16)"
add_missing GF_SECURITY_ADMIN_PASSWORD "$(openssl rand -hex 16)"
add_missing GITLAB_HOOK_TOKEN "$(openssl rand -hex 24)"

# Mattermost DB: the postgres container and the app must agree on one password,
# so the full DSN is written here too (Quadlet cannot interpolate one env var into another).
add_missing MM_DB_PASSWORD "$(openssl rand -hex 24)"
add_missing POSTGRES_PASSWORD "$(get MM_DB_PASSWORD)"
add_missing MM_SQLSETTINGS_DATASOURCE \
  "postgres://mmuser:$(get MM_DB_PASSWORD)@mattermost-db:5432/mattermost?sslmode=disable"

if [[ ! -f $PORTAINER_PW ]]; then
  openssl rand -hex 16 > "$PORTAINER_PW"
  echo "created $PORTAINER_PW"
fi
