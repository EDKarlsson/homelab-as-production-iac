#!/usr/bin/env bash
# k3s-ssh.sh — SSH into K3s cluster VMs via 1Password SSH agent
#
# Usage:
#   ./k3s-ssh.sh <ip|role>           # Interactive SSH session
#   ./k3s-ssh.sh <ip|role> <command> # Run command remotely
#   ./k3s-ssh.sh --list              # List all VMs
#   ./k3s-ssh.sh --setup             # Extract SSH key from 1Password agent
#
# Roles: server1, server2, server3, agent1-agent5, postgres (VIP), postgres-primary, postgres-standby, all
#
# Prerequisites:
#   - 1Password desktop app running with SSH agent enabled
#   - SSH key "homelab-k3s-cluster" configured in 1Password
#
# Examples:
#   ./k3s-ssh.sh server1 'hostname'
#   ./k3s-ssh.sh postgres 'sudo systemctl status postgresql'
#   ./k3s-ssh.sh 10.0.0.50 'sudo k3s kubectl get nodes'
#   ./k3s-ssh.sh all 'cloud-init status'

set -euo pipefail

# --- Configuration ---
K3S_USER="k3sadmin"
K3S_KEY_PUB="/tmp/k3s-key.pub"
K3S_KEY_NAME="homelab-k3s-cluster"
OP_SSH_SOCK="${HOME}/.1password/agent.sock"

# Cluster IP map (lexicographic order matches Terraform's keys() ordering)
declare -A VM_IPS=(
  [server1]="10.0.0.50"   # node-02
  [server2]="10.0.0.51"   # node-03
  [server3]="10.0.0.52"   # node-04
  [agent1]="10.0.0.60"    # node-01
  [agent2]="10.0.0.61"    # node-05
  [agent3]="10.0.0.62"    # node-02
  [agent4]="10.0.0.63"    # node-03
  [agent5]="10.0.0.64"    # node-04
  [postgres]="10.0.0.44"          # VIP (keepalived, active primary)
  [postgres-primary]="10.0.0.45"  # node-01 (VM 520)
  [postgres-standby]="10.0.0.46"  # node-05 (VM 521)
)

SERVERS=(10.0.0.50 10.0.0.51 10.0.0.52)
AGENTS=(10.0.0.60 10.0.0.61 10.0.0.62 10.0.0.63 10.0.0.64)
ALL_IPS=("${SERVERS[@]}" "${AGENTS[@]}" 10.0.0.45 10.0.0.46)

# --- Functions ---
setup_key() {
  if [[ ! -S "$OP_SSH_SOCK" ]]; then
    echo "ERROR: 1Password SSH agent socket not found at $OP_SSH_SOCK"
    echo "       Make sure 1Password desktop app is running with SSH agent enabled."
    exit 1
  fi

  SSH_AUTH_SOCK="$OP_SSH_SOCK" ssh-add -L | grep "$K3S_KEY_NAME" > "$K3S_KEY_PUB" 2>/dev/null
  if [[ ! -s "$K3S_KEY_PUB" ]]; then
    echo "ERROR: Key '$K3S_KEY_NAME' not found in 1Password SSH agent."
    echo "       Available keys:"
    SSH_AUTH_SOCK="$OP_SSH_SOCK" ssh-add -L | awk '{print "         " $3}'
    exit 1
  fi
  chmod 600 "$K3S_KEY_PUB"
  echo "SSH key extracted to $K3S_KEY_PUB"
}

ensure_key() {
  if [[ ! -f "$K3S_KEY_PUB" ]] || [[ ! -s "$K3S_KEY_PUB" ]]; then
    setup_key
  fi
}

do_ssh() {
  local ip="$1"
  shift
  ensure_key
  SSH_AUTH_SOCK="$OP_SSH_SOCK" ssh \
    -o ConnectTimeout=5 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o IdentitiesOnly=yes \
    -o LogLevel=ERROR \
    -i "$K3S_KEY_PUB" \
    "${K3S_USER}@${ip}" "$@"
}

resolve_ip() {
  local target="$1"
  # If it's already an IP, return as-is
  if [[ "$target" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "$target"
    return
  fi
  # Look up role name
  if [[ -n "${VM_IPS[$target]+x}" ]]; then
    echo "${VM_IPS[$target]}"
    return
  fi
  echo "ERROR: Unknown target '$target'. Use --list to see available targets." >&2
  exit 1
}

list_vms() {
  echo "K3s Cluster VMs:"
  echo ""
  printf "  %-18s %-16s %s\n" "Role" "IP" "Proxmox Node"
  printf "  %-18s %-16s %s\n" "----" "--" "------------"
  printf "  %-18s %-16s %s\n" "server1" "10.0.0.50" "node-02"
  printf "  %-18s %-16s %s\n" "server2" "10.0.0.51" "node-03"
  printf "  %-18s %-16s %s\n" "server3" "10.0.0.52" "node-04"
  printf "  %-18s %-16s %s\n" "agent1" "10.0.0.60" "node-01"
  printf "  %-18s %-16s %s\n" "agent2" "10.0.0.61" "node-05"
  printf "  %-18s %-16s %s\n" "agent3" "10.0.0.62" "node-02"
  printf "  %-18s %-16s %s\n" "agent4" "10.0.0.63" "node-03"
  printf "  %-18s %-16s %s\n" "agent5" "10.0.0.64" "node-04"
  echo ""
  echo "PostgreSQL HA Cluster:"
  echo ""
  printf "  %-18s %-16s %s\n" "Role" "IP" "Node"
  printf "  %-18s %-16s %s\n" "----" "--" "----"
  printf "  %-18s %-16s %s\n" "postgres" "10.0.0.44" "VIP (keepalived)"
  printf "  %-18s %-16s %s\n" "postgres-primary" "10.0.0.45" "node-01 (VM 520)"
  printf "  %-18s %-16s %s\n" "postgres-standby" "10.0.0.46" "node-05 (VM 521)"
}

# --- Main ---
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <ip|role|--list|--setup|all> [command]"
  exit 1
fi

case "$1" in
  --list|-l)
    list_vms
    ;;
  --setup|-s)
    setup_key
    ;;
  all)
    shift
    for ip in "${ALL_IPS[@]}"; do
      echo "=== $ip ==="
      do_ssh "$ip" "$@" 2>&1 || echo "  FAILED"
      echo ""
    done
    ;;
  servers)
    shift
    for ip in "${SERVERS[@]}"; do
      echo "=== $ip ==="
      do_ssh "$ip" "$@" 2>&1 || echo "  FAILED"
      echo ""
    done
    ;;
  agents)
    shift
    for ip in "${AGENTS[@]}"; do
      echo "=== $ip ==="
      do_ssh "$ip" "$@" 2>&1 || echo "  FAILED"
      echo ""
    done
    ;;
  *)
    ip=$(resolve_ip "$1")
    shift
    do_ssh "$ip" "$@"
    ;;
esac
