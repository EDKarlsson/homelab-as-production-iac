#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# AppArmor inside LXC blocks Docker from applying container profiles.
# The host's AppArmor already confines the LXC, so inner AppArmor is redundant.
if dpkg -l apparmor &>/dev/null 2>&1; then
  echo "=== Removing AppArmor (incompatible with Docker-in-LXC) ==="
  apt-get remove -y -qq apparmor
fi

if command -v docker &>/dev/null; then
  echo "=== Docker already installed, skipping ==="
else
  echo "=== Installing Docker CE ==="
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi

if command -v keepalived &>/dev/null; then
  echo "=== keepalived already installed, skipping ==="
else
  echo "=== Installing keepalived ==="
  apt-get install -y -qq keepalived
fi

echo "=== Setting up 1Password Connect ==="
mkdir -p /opt/op-connect/data
# Connect containers run as opuser (999:999); data dir must be writable
chown -R 999:999 /opt/op-connect/data

# Decode credentials from provisioner-uploaded file
base64 -d /tmp/op-credentials.b64 > /opt/op-connect/1password-credentials.json
# 644 so opuser (UID 999) inside Connect containers can read the file
chmod 644 /opt/op-connect/1password-credentials.json

# Move config files to final locations (idempotent — skip if already moved)
[ -f /tmp/docker-compose.yml ] && mv /tmp/docker-compose.yml /opt/op-connect/docker-compose.yml
mkdir -p /etc/keepalived
[ -f /tmp/keepalived.conf ] && mv /tmp/keepalived.conf /etc/keepalived/keepalived.conf
[ -f /tmp/op-connect.service ] && mv /tmp/op-connect.service /etc/systemd/system/op-connect.service

echo "=== Starting services ==="
systemctl daemon-reload
systemctl enable --now docker
systemctl enable --now op-connect.service
systemctl enable --now keepalived

# Clean up temp files
rm -f /tmp/op-credentials.b64 /tmp/setup.sh

echo "=== Health check ==="
for i in $(seq 1 12); do
  if curl -sf http://localhost:8080/heartbeat >/dev/null 2>&1; then
    echo "1Password Connect is healthy!"
    exit 0
  fi
  echo "Waiting for Connect to start... ($i/12)"
  sleep 5
done

echo "WARNING: Connect did not become healthy within 60s"
exit 1
