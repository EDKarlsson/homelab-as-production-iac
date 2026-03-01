#!/usr/bin/env bash
# vfio-check.sh — Diagnose VFIO/IOMMU readiness on a Proxmox host
#
# Checks IOMMU group isolation, driver bindings, EFI framebuffer state,
# and vfio-pci modprobe config. Run this BEFORE attempting GPU passthrough.
#
# Usage:
#   ./vfio-check.sh                    # Check local host (run directly on PVE node)
#   ./vfio-check.sh <pci_id> [...]     # Check specific PCI IDs (e.g. 0000:65:00.0)
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more checks failed (see output)

set -euo pipefail

# Default PCI IDs for ComfyUI RTX 3060 on gpu-workstation
# Override by passing PCI IDs as arguments
PCI_IDS=("${@:-0000:65:00.0 0000:65:00.1}")
if [[ $# -gt 0 ]]; then
  PCI_IDS=("$@")
else
  PCI_IDS=(0000:65:00.0 0000:65:00.1)
fi

PASS=0
FAIL=0
WARN=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
warn() { echo "  WARN: $1"; WARN=$((WARN + 1)); }
header() { echo ""; echo "=== $1 ==="; }

# --- 1. IOMMU active ---
header "IOMMU"
if grep -q "intel_iommu=on\|amd_iommu=on" /proc/cmdline; then
  pass "IOMMU enabled in kernel cmdline"
else
  fail "IOMMU not enabled — add intel_iommu=on (Intel) or amd_iommu=on (AMD) to GRUB"
fi

# Confirm via iommu_groups directory — if groups exist, IOMMU is active regardless of dmesg message format
if [[ -d /sys/kernel/iommu_groups ]] && [[ $(find /sys/kernel/iommu_groups -maxdepth 1 -mindepth 1 | wc -l) -gt 0 ]]; then
  group_count=$(find /sys/kernel/iommu_groups -maxdepth 1 -mindepth 1 | wc -l)
  pass "IOMMU active — $group_count IOMMU groups found in sysfs"
elif dmesg | grep -qi "IOMMU enabled\|DMAR: IOMMU enabled\|AMD-Vi: AMD IOMMU initialized\|DMAR:.*IOMMU"; then
  pass "IOMMU initialized (dmesg confirms)"
else
  warn "Could not confirm IOMMU initialization — check dmesg manually"
fi

if grep -q "iommu=pt" /proc/cmdline; then
  pass "iommu=pt (passthrough mode) active — host devices use identity mapping"
else
  warn "iommu=pt not set — recommended for performance on host devices"
fi

# --- 2. Driver bindings ---
header "Driver Bindings"
for pci in "${PCI_IDS[@]}"; do
  if [[ ! -e "/sys/bus/pci/devices/$pci" ]]; then
    fail "$pci — device not found"
    continue
  fi
  driver=$(readlink "/sys/bus/pci/devices/$pci/driver" 2>/dev/null | xargs basename 2>/dev/null || echo "none")
  if [[ "$driver" == "vfio-pci" ]]; then
    pass "$pci → vfio-pci (correct for passthrough)"
  elif [[ "$driver" == "none" ]]; then
    warn "$pci → no driver bound (device available but not claimed by vfio-pci)"
  else
    fail "$pci → $driver (should be vfio-pci for passthrough)"
  fi
done

# --- 3. IOMMU group isolation ---
header "IOMMU Group Isolation"
echo "  Listing all IOMMU groups for passthrough PCI IDs:"
echo ""

all_clean=true
for pci in "${PCI_IDS[@]}"; do
  [[ ! -e "/sys/bus/pci/devices/$pci" ]] && continue

  # Find which group this device is in
  group_path=$(readlink -f "/sys/bus/pci/devices/$pci/iommu_group")
  group_num=$(basename "$group_path")

  echo "  $pci is in IOMMU group $group_num:"
  while IFS= read -r dev_path; do
    dev=$(basename "$dev_path")
    info=$(lspci -nns "$dev" 2>/dev/null || echo "$dev (lspci failed)")
    class=$(echo "$info" | grep -oP '\[\K[0-9a-f]{4}(?=\])' | head -1)
    echo "    $info"
    # PCIe Root Port class = 0604, PCI Bridge = 0600
    if [[ "$class" == "0604" || "$class" == "0600" ]]; then
      all_clean=false
    fi
  done < <(find "/sys/kernel/iommu_groups/$group_num/devices" -mindepth 1 -maxdepth 1)
  echo ""
done

if $all_clean; then
  pass "No PCIe root ports or bridges share a group with passthrough devices"
else
  fail "PCIe root port or bridge found in passthrough device group — ACS override or slot change needed"
fi

# --- 4. EFI framebuffer (BOOTFB) ---
header "EFI Framebuffer"
if grep -qi "bootfb\|simplefb" /proc/iomem 2>/dev/null; then
  fail "BOOTFB/simplefb found in /proc/iomem — EFI framebuffer is holding GPU BARs"
  echo "  Fix: add 'initcall_blacklist=sysfb_init' to GRUB_CMDLINE_LINUX_DEFAULT"
  grep -i "bootfb\|simplefb" /proc/iomem | sed 's/^/  /'
else
  pass "No BOOTFB/simplefb entry in /proc/iomem — GPU BARs not held by host framebuffer"
fi

if grep -q "initcall_blacklist=sysfb_init" /proc/cmdline; then
  pass "initcall_blacklist=sysfb_init active in kernel cmdline"
else
  warn "initcall_blacklist=sysfb_init not in cmdline — EFI framebuffer may grab GPU BARs"
fi

# --- 5. vfio-pci modprobe config ---
header "vfio-pci Modprobe Config"
vfio_conf="/etc/modprobe.d/vfio.conf"
if [[ -f "$vfio_conf" ]]; then
  pass "$vfio_conf exists"
  sed 's/^/  /' "$vfio_conf"
  if grep -q "disable_vga=1" "$vfio_conf"; then
    pass "disable_vga=1 set — VGA arbitration disabled for passthrough GPUs"
  else
    fail "disable_vga=1 not set in vfio.conf — add it to prevent VGA arbitration interference"
  fi
else
  fail "$vfio_conf not found — create it with: options vfio-pci ids=<vid:did,...> disable_vga=1"
fi

# --- 6. ROM BAR config in VM ---
header "VM hostpci Config (informational)"
echo "  Check VM .conf files for rombar setting:"
mapfile -t hostpci_vms < <(find /etc/pve/nodes -name "*.conf" -exec grep -l "hostpci" {} + 2>/dev/null | head -5 || true)
if [[ ${#hostpci_vms[@]} -gt 0 ]]; then
  for f in "${hostpci_vms[@]}"; do
    vmid=$(basename "$f" .conf)
    echo "  VM $vmid:"
    grep "^hostpci" "$f" | sed 's/^/    /'
  done
  pass "VM hostpci configs shown above -- verify rombar=0 for CUDA-only GPUs"
else
  echo "  No VMs with hostpci config found on this node"
fi
# --- Summary ---
echo ""
echo "========================================"
echo "  VFIO Readiness Summary"
echo "========================================"
echo "  PASS: $PASS"
echo "  WARN: $WARN"
echo "  FAIL: $FAIL"
echo ""
if [[ $FAIL -gt 0 ]]; then
  echo "  Action required — see FAIL items above"
  exit 1
elif [[ $WARN -gt 0 ]]; then
  echo "  Review WARN items before starting passthrough VM"
  exit 0
else
  echo "  All checks passed — VFIO passthrough should be ready"
  exit 0
fi
