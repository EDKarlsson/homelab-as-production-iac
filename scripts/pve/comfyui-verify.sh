#!/usr/bin/env bash
# comfyui-verify.sh — Verify ComfyUI VM is healthy after deployment
#
# Checks: SSH access, cloud-init completion, NVIDIA driver, Docker, ComfyUI port.
# Run from the workstation after terraform apply + cloud-init completes (~5-10 min).
#
# Usage:
#   ./comfyui-verify.sh                  # Use default IP (10.0.0.53)
#   ./comfyui-verify.sh <ip>             # Use specific IP
#   ./comfyui-verify.sh --wait           # Wait for VM to come up (up to 10 min)
#
# Requires: SSH_AUTH_SOCK pointing to 1Password agent, public key at ./k3s-cluster.pub
# (or set COMFY_SSH_KEY env var to path of public key for IdentitiesOnly pinning)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VM_IP="${1:-10.0.0.53}"
VM_USER="comfyadmin"
COMFY_PORT=8188
WAIT_MODE=false
if [[ "${1:-}" == "--wait" ]] || [[ "${2:-}" == "--wait" ]]; then
  WAIT_MODE=true
  [[ "${1:-}" != "--wait" ]] && VM_IP="${1:-10.0.0.53}"
fi

# SSH key: use env var, fall back to k3s cluster key in ansible dir
SSH_KEY="${COMFY_SSH_KEY:-}"
if [[ -z "$SSH_KEY" ]]; then
  candidates=(
    "$SCRIPT_DIR/../../ansible/.ssh/k3s-cluster.pub"
    "/tmp/k3s-key.pub"
  )
  for c in "${candidates[@]}"; do
    if [[ -f "$c" ]]; then SSH_KEY="$c"; break; fi
  done
fi

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5"
if [[ -n "$SSH_KEY" ]]; then
  SSH_OPTS="$SSH_OPTS -o IdentitiesOnly=yes -i $SSH_KEY"
fi

PASS=0
FAIL=0
WARN=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
warn() { echo "  WARN: $1"; WARN=$((WARN + 1)); }
header() { echo ""; echo "=== $1 ==="; }

# shellcheck disable=SC2086,SC2029  # SSH_OPTS is intentionally word-split; args expand client-side
vm_ssh() { ssh $SSH_OPTS "$VM_USER@$VM_IP" "$@" 2>/dev/null; }

# --- 0. Wait for SSH (optional) ---
if $WAIT_MODE; then
  header "Waiting for VM ($VM_IP)"
  echo "  Polling SSH every 20s, up to 10 minutes..."
  for i in $(seq 1 30); do
    if vm_ssh 'echo ok' &>/dev/null; then
      echo "  VM online after ~$((i * 20))s"
      break
    fi
    if [[ $i -eq 30 ]]; then
      echo "  FAIL: Timed out waiting for VM to come up"
      exit 1
    fi
    printf "  Attempt %d/30 (%s)...\n" "$i" "$(date +%H:%M:%S)"
    sleep 20
  done
fi

# --- 1. SSH reachability ---
header "SSH ($VM_USER@$VM_IP)"
if vm_ssh 'hostname' 2>/dev/null; then
  pass "SSH access OK"
  hostname=$(vm_ssh 'hostname')
  echo "  hostname: $hostname"
else
  fail "SSH failed — VM may not be up or key not recognized"
  echo ""
  echo "  Tip: try --wait to poll until VM is ready"
  exit 1
fi

# --- 2. Cloud-init ---
header "Cloud-init"
ci_status=$(vm_ssh 'cloud-init status 2>/dev/null || echo unknown')
echo "  cloud-init status: $ci_status"
if echo "$ci_status" | grep -q "done"; then
  pass "Cloud-init completed"
elif echo "$ci_status" | grep -q "running"; then
  warn "Cloud-init still running — wait a few minutes and re-run"
elif echo "$ci_status" | grep -q "error"; then
  fail "Cloud-init reported error"
  vm_ssh 'sudo cloud-init status --long 2>/dev/null' | sed 's/^/  /' || true
else
  warn "Cloud-init status unknown: $ci_status"
fi

# --- 3. NVIDIA driver ---
header "NVIDIA Driver"
if vm_ssh 'command -v nvidia-smi' &>/dev/null; then
  nvidia_out=$(vm_ssh 'nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader 2>/dev/null')
  if [[ -n "$nvidia_out" ]]; then
    pass "nvidia-smi working"
    # shellcheck disable=SC2001  # multi-line prefix requires sed, not bash substitution
    echo "$nvidia_out" | sed 's/^/  GPU: /'
  else
    fail "nvidia-smi found but returned no output"
    vm_ssh 'nvidia-smi 2>&1' | head -10 | sed 's/^/  /' || true
  fi
else
  fail "nvidia-smi not found — NVIDIA driver not installed or GPU not detected"
  echo "  Check: sudo dmesg | grep -i nvidia"
  echo "  Check: lspci | grep -i nvidia"
fi

# --- 4. Docker ---
header "Docker"
if vm_ssh 'docker info &>/dev/null'; then
  pass "Docker daemon running"
  containers=$(vm_ssh 'docker ps --format "{{.Names}} ({{.Status}})" 2>/dev/null' || echo "none")
  if [[ -n "$containers" && "$containers" != "none" ]]; then
    pass "Containers running:"
    # shellcheck disable=SC2001  # multi-line prefix requires sed, not bash substitution
    echo "$containers" | sed 's/^/    /'
  else
    warn "Docker running but no containers up — ComfyUI may still be starting"
  fi
else
  fail "Docker not running or not accessible"
fi

# --- 5. NVIDIA Container Toolkit ---
header "NVIDIA Container Toolkit"
if vm_ssh 'docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi' &>/dev/null; then
  pass "GPU accessible from Docker container"
else
  warn "GPU not accessible from Docker — nvidia-container-toolkit may not be configured"
  echo "  Check: sudo nvidia-ctk runtime configure --runtime=docker"
fi

# --- 6. ComfyUI port ---
header "ComfyUI Web UI (port $COMFY_PORT)"
if vm_ssh "curl -s --max-time 5 http://localhost:$COMFY_PORT | head -c 100" 2>/dev/null | grep -qi "html\|comfy\|react"; then
  pass "ComfyUI responding on port $COMFY_PORT"
  echo "  Access at: http://$VM_IP:$COMFY_PORT"
else
  warn "ComfyUI not yet responding on port $COMFY_PORT — may still be starting"
  echo "  Check logs: docker logs comfyui"
  echo "  Check status: docker ps"
fi

# --- Summary ---
echo ""
echo "========================================"
echo "  ComfyUI Verification Summary"
echo "========================================"
echo "  PASS: $PASS"
echo "  WARN: $WARN"
echo "  FAIL: $FAIL"
echo ""
if [[ $FAIL -gt 0 ]]; then
  echo "  Deployment has failures — see above"
  exit 1
elif [[ $WARN -gt 0 ]]; then
  echo "  Deployment functional with warnings — check WARN items"
  exit 0
else
  echo "  ComfyUI deployment fully verified"
  echo "  Web UI: http://$VM_IP:$COMFY_PORT"
  exit 0
fi
