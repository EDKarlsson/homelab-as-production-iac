#!/usr/bin/env bash
# k3s-verify.sh — End-to-end verification of K3s cluster deployment
#
# Runs all verification phases sequentially and reports results.
# Uses k3s-ssh.sh for SSH access.
#
# Usage:
#   ./k3s-verify.sh              # Run all phases
#   ./k3s-verify.sh <phase>      # Run specific phase (1-7)
#   ./k3s-verify.sh --quick      # Quick check (phases 1-3 only)
#
# Phases:
#   1 - Network reachability (ping)
#   2 - SSH access
#   3 - Cloud-init status
#   4 - K3s server health
#   5 - K3s agent health
#   6 - PostgreSQL health
#   7 - Full cluster validation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K3S_SSH="$SCRIPT_DIR/k3s-ssh.sh"

# Cluster IPs
SERVERS=(10.0.0.50 10.0.0.51 10.0.0.52)
AGENTS=(10.0.0.60 10.0.0.61 10.0.0.62 10.0.0.63 10.0.0.64)
POSTGRES_PRIMARY="10.0.0.45"
POSTGRES_STANDBY="10.0.0.46"
POSTGRES_VIP="10.0.0.44"
ALL_IPS=("${SERVERS[@]}" "${AGENTS[@]}" "$POSTGRES_PRIMARY" "$POSTGRES_STANDBY")

# Counters
PASS=0
FAIL=0
WARN=0

# --- Helpers ---
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
warn() { echo "  WARN: $1"; WARN=$((WARN + 1)); }

ssh_cmd() {
  local ip="$1"; shift
  "$K3S_SSH" "$ip" "$@" 2>/dev/null
}

# --- Phase 1: Network Reachability ---
phase_1() {
  echo ""
  echo "=== Phase 1: Network Reachability ==="
  for ip in "${ALL_IPS[@]}"; do
    if ping -c 1 -W 2 "$ip" &>/dev/null; then
      pass "$ip reachable"
    else
      fail "$ip UNREACHABLE"
    fi
  done
}

# --- Phase 2: SSH Access ---
phase_2() {
  echo ""
  echo "=== Phase 2: SSH Access ==="
  for ip in "${ALL_IPS[@]}"; do
    hostname=$(ssh_cmd "$ip" 'hostname' 2>/dev/null) || hostname=""
    if [[ -n "$hostname" ]]; then
      pass "$ip → $hostname"
    else
      fail "$ip SSH failed"
    fi
  done
}

# --- Phase 3: Cloud-init Status ---
phase_3() {
  echo ""
  echo "=== Phase 3: Cloud-Init Status ==="
  for ip in "${ALL_IPS[@]}"; do
    status=$(ssh_cmd "$ip" 'cloud-init status 2>/dev/null' 2>/dev/null || true)
    hostname=$(ssh_cmd "$ip" 'hostname' 2>/dev/null || true)
    [[ -z "$status" ]] && status="unknown"
    [[ -z "$hostname" ]] && hostname="$ip"
    case "$status" in
      *done*)
        pass "$hostname ($ip): done"
        ;;
      *running*)
        warn "$hostname ($ip): still running"
        ;;
      *error*)
        # Check if it's the non-fatal write_files error or something worse
        detail=$(ssh_cmd "$ip" 'cloud-init status --long 2>/dev/null | grep errors: -A5' 2>/dev/null) || detail=""
        if echo "$detail" | grep -q "write_files"; then
          warn "$hostname ($ip): error (write_files only — non-fatal)"
        else
          fail "$hostname ($ip): error"
          echo "    Detail: $detail"
        fi
        ;;
      *)
        fail "$hostname ($ip): $status"
        ;;
    esac
  done
}

# --- Phase 4: K3s Server Health ---
phase_4() {
  echo ""
  echo "=== Phase 4: K3s Server Health ==="
  for ip in "${SERVERS[@]}"; do
    hostname=$(ssh_cmd "$ip" 'hostname' 2>/dev/null) || hostname="$ip"
    k3s_status=$(ssh_cmd "$ip" 'sudo systemctl is-active k3s 2>/dev/null' 2>/dev/null) || k3s_status="unknown"

    if [[ "$k3s_status" == "active" ]]; then
      pass "$hostname ($ip): k3s active"
      # Check node ready
      # shellcheck disable=SC2016  # single quotes intentional: $(hostname) evaluated on remote host
      node_status=$(ssh_cmd "$ip" 'sudo k3s kubectl get node $(hostname) -o jsonpath="{.status.conditions[?(@.type==\"Ready\")].status}" 2>/dev/null' 2>/dev/null) || node_status=""
      if [[ "$node_status" == "True" ]]; then
        pass "$hostname ($ip): node Ready"
      else
        warn "$hostname ($ip): node not Ready (status: $node_status)"
      fi
    elif [[ "$k3s_status" == "activating" ]]; then
      warn "$hostname ($ip): k3s activating (still starting)"
    else
      fail "$hostname ($ip): k3s $k3s_status"
      # Show last few log lines
      echo "    Recent logs:"
      ssh_cmd "$ip" 'sudo journalctl -u k3s --no-pager -n 5 2>/dev/null | sed "s/^/    /"' 2>/dev/null || true
    fi
  done
}

# --- Phase 5: K3s Agent Health ---
phase_5() {
  echo ""
  echo "=== Phase 5: K3s Agent Health ==="
  for ip in "${AGENTS[@]}"; do
    hostname=$(ssh_cmd "$ip" 'hostname' 2>/dev/null) || hostname="$ip"
    agent_status=$(ssh_cmd "$ip" 'sudo systemctl is-active k3s-agent 2>/dev/null' 2>/dev/null) || agent_status="unknown"

    if [[ "$agent_status" == "active" ]]; then
      pass "$hostname ($ip): k3s-agent active"
    elif [[ "$agent_status" == "activating" ]]; then
      warn "$hostname ($ip): k3s-agent activating"
    else
      fail "$hostname ($ip): k3s-agent $agent_status"
      # Check if K3s is even installed
      k3s_installed=$(ssh_cmd "$ip" 'which k3s 2>/dev/null' 2>/dev/null) || k3s_installed=""
      if [[ -z "$k3s_installed" ]]; then
        echo "    k3s not installed (cloud-init runcmd may still be running)"
      else
        echo "    Recent logs:"
        ssh_cmd "$ip" 'sudo journalctl -u k3s-agent --no-pager -n 5 2>/dev/null | sed "s/^/    /"' 2>/dev/null || true
      fi
    fi
  done
}

# --- Phase 6: PostgreSQL HA Health ---
phase_6() {
  echo ""
  echo "=== Phase 6: PostgreSQL HA Health ==="

  # Check both PG nodes
  for pg_ip in "$POSTGRES_PRIMARY" "$POSTGRES_STANDBY"; do
    hostname=$(ssh_cmd "$pg_ip" 'hostname' 2>/dev/null) || hostname="$pg_ip"
    pg_status=$(ssh_cmd "$pg_ip" 'sudo systemctl is-active postgresql 2>/dev/null' 2>/dev/null) || pg_status="unknown"

    if [[ "$pg_status" == "active" ]]; then
      pass "$hostname ($pg_ip): postgresql active"
    else
      fail "$hostname ($pg_ip): postgresql $pg_status"
    fi

    # Check replication role
    is_recovery=$(ssh_cmd "$pg_ip" "sudo -u postgres psql -t -c \"SELECT pg_is_in_recovery();\" 2>/dev/null" 2>/dev/null | tr -d ' ') || is_recovery="unknown"
    if [[ "$is_recovery" == "f" ]]; then
      pass "$hostname ($pg_ip): role=primary"
    elif [[ "$is_recovery" == "t" ]]; then
      pass "$hostname ($pg_ip): role=standby"
    else
      warn "$hostname ($pg_ip): role unknown ($is_recovery)"
    fi

    # Check data disk mounted
    data_mount=$(ssh_cmd "$pg_ip" 'df -h /mnt/data 2>/dev/null | tail -1' 2>/dev/null) || data_mount=""
    if [[ -n "$data_mount" ]] && echo "$data_mount" | grep -q "/mnt/data"; then
      pass "$hostname ($pg_ip): data disk mounted at /mnt/data"
    else
      warn "$hostname ($pg_ip): data disk not mounted at /mnt/data"
    fi
  done

  # Check databases exist (via primary)
  dbs=$(ssh_cmd "$POSTGRES_PRIMARY" 'sudo -u postgres psql -t -c "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname;" 2>/dev/null' 2>/dev/null) || dbs=""
  if echo "$dbs" | grep -q "k3s"; then
    pass "Database 'k3s' exists"
  else
    fail "Database 'k3s' not found"
  fi
  if echo "$dbs" | grep -q "terraform_state"; then
    pass "Database 'terraform_state' exists"
  else
    fail "Database 'terraform_state' not found"
  fi

  # Check VIP connectivity from a K3s server
  echo ""
  echo "  Testing VIP ($POSTGRES_VIP) connectivity from K3s server..."
  remote_test=$(ssh_cmd "${SERVERS[0]}" "bash -c 'echo > /dev/tcp/$POSTGRES_VIP/5432 && echo open || echo closed' 2>&1" 2>/dev/null || true)
  if echo "$remote_test" | grep -q "open"; then
    pass "VIP $POSTGRES_VIP → PostgreSQL port 5432 open from ${SERVERS[0]}"
  else
    fail "VIP $POSTGRES_VIP not reachable from ${SERVERS[0]}: $remote_test"
  fi
}

# --- Phase 7: Full Cluster Validation ---
phase_7() {
  echo ""
  echo "=== Phase 7: Full Cluster Validation ==="
  # Run from first server
  echo "  Querying cluster from ${SERVERS[0]}..."
  echo ""

  echo "  --- Nodes ---"
  ssh_cmd "${SERVERS[0]}" 'sudo k3s kubectl get nodes -o wide 2>/dev/null' 2>/dev/null | sed 's/^/  /' || fail "Cannot get nodes"
  echo ""

  node_count=$(ssh_cmd "${SERVERS[0]}" 'sudo k3s kubectl get nodes --no-headers 2>/dev/null | wc -l' 2>/dev/null) || node_count=0
  if [[ "$node_count" -eq 8 ]]; then
    pass "All 8 nodes in cluster (3 servers + 5 agents)"
  elif [[ "$node_count" -gt 0 ]]; then
    warn "$node_count/8 nodes in cluster"
  else
    fail "No nodes found in cluster"
    return
  fi

  ready_count=$(ssh_cmd "${SERVERS[0]}" 'sudo k3s kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready "' 2>/dev/null) || ready_count=0
  if [[ "$ready_count" -eq "$node_count" ]]; then
    pass "All $ready_count nodes Ready"
  else
    warn "$ready_count/$node_count nodes Ready"
  fi

  echo ""
  echo "  --- System Pods ---"
  ssh_cmd "${SERVERS[0]}" 'sudo k3s kubectl get pods -n kube-system 2>/dev/null' 2>/dev/null | sed 's/^/  /' || warn "Cannot list system pods"

  echo ""
  echo "  --- Cluster Info ---"
  ssh_cmd "${SERVERS[0]}" 'sudo k3s kubectl cluster-info 2>/dev/null' 2>/dev/null | sed 's/^/  /' || warn "Cannot get cluster info"
}

# --- Summary ---
summary() {
  echo ""
  echo "========================================="
  echo "  PASS: $PASS  |  WARN: $WARN  |  FAIL: $FAIL"
  echo "========================================="
  if [[ $FAIL -gt 0 ]]; then
    echo "  Some checks failed. Review output above."
    exit 1
  elif [[ $WARN -gt 0 ]]; then
    echo "  Passed with warnings."
    exit 0
  else
    echo "  All checks passed!"
    exit 0
  fi
}

# --- Main ---
echo "K3s Cluster Deployment Verification"
date

case "${1:-all}" in
  1) phase_1 ;;
  2) phase_2 ;;
  3) phase_3 ;;
  4) phase_4 ;;
  5) phase_5 ;;
  6) phase_6 ;;
  7) phase_7 ;;
  --quick|-q)
    phase_1
    phase_2
    phase_3
    ;;
  all|"")
    phase_1
    phase_2
    phase_3
    phase_4
    phase_5
    phase_6
    phase_7
    ;;
  *)
    echo "Usage: $0 [1-7|--quick|all]"
    exit 1
    ;;
esac

summary
