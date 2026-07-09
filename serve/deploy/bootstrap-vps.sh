#!/usr/bin/env bash
# One-time VPS bootstrap for the registry query API (run by a human, as root, on the box).
# Installs Docker + Compose + sqlite3, creates the app dirs, and prints the remaining
# manual steps (deploy key, DNS, AMR_API_HOST, GitHub repo variable/secrets).
set -euo pipefail

APP="${AMR_APP_DIR:-/opt/amr-api}"
DEPLOY_USER="${AMR_DEPLOY_USER:-deploy}"

echo "==> Installing Docker, Compose plugin, sqlite3, rsync, git"
if command -v apt-get >/dev/null; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl git rsync sqlite3
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
else
  echo "Non-apt host: install docker + 'docker compose' plugin + sqlite3 manually, then re-run." >&2
  exit 1
fi

echo "==> Creating $DEPLOY_USER and app dirs under $APP"
id "$DEPLOY_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$DEPLOY_USER"
usermod -aG docker "$DEPLOY_USER"
mkdir -p "$APP/serve" "$APP/data"
chown -R "$DEPLOY_USER":"$DEPLOY_USER" "$APP"

cat <<EOF

==> Done. Remaining manual steps:
  1. Add the CI deploy public key to ~$DEPLOY_USER/.ssh/authorized_keys (private half -> GitHub secret VPS_SSH_KEY).
  2. Point a DNS A record at this box; open ports 80 and 443 (Caddy ACME needs both).
  3. Put the hostname in the compose env:  echo 'AMR_API_HOST=api.example.org' >> $APP/serve/.env
     (or export AMR_API_HOST before the first compose up; ':80' serves plain HTTP with no cert).
  4. In the GitHub repo, set:
       - variable  AMR_API_DEPLOY_ENABLED = true   (turns the deploy-api workflow on)
       - secrets   VPS_HOST, VPS_USER ($DEPLOY_USER), VPS_SSH_KEY
  5. Trigger the 'deploy-api' workflow (push to main touching serve/**, or run it manually).
EOF
