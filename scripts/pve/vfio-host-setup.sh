#!/usr/bin/env bash
# vfio-host-setup.sh — Apply VFIO/GPU passthrough host-side config on a Proxmox node
#
# Idempotent: safe to run multiple times. Makes three changes:
#   1. Adds initcall_blacklist=sysfb_init to GRUB (prevents EFI framebuffer holding GPU BARs)
#   2. Creates/updates /etc/modprobe.d/vfio.conf with disable_vga=1
#   3. Runs update-grub + update-initramfs
#
# A reboot is required for changes to take effect.
#
# Usage (run directly on the Proxmox host as root):
#   ./vfio-host-setup.sh <vid:did> [vid:did ...]
#
# Example:
#   ./vfio-host-setup.sh 10de:2504 10de:228e   # RTX 3060 VGA + audio
#
# Must run as root.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: must run as root" >&2
  exit 1
fi

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <vid:did> [vid:did ...]"
  echo "Example: $0 10de:2504 10de:228e"
  exit 1
fi

IDS=$(IFS=','; echo "$*")

changed=false
grub_file="/etc/default/grub"
vfio_conf="/etc/modprobe.d/vfio.conf"

echo "=== vfio-host-setup.sh ==="
echo "  PCI IDs: $IDS"
echo ""

# --- 1. GRUB: initcall_blacklist=sysfb_init ---
echo "--- GRUB (initcall_blacklist=sysfb_init) ---"
if grep -q "initcall_blacklist=sysfb_init" "$grub_file"; then
  echo "  Already present — no change"
else
  # Insert before the closing quote of GRUB_CMDLINE_LINUX_DEFAULT
  sed -i 's/\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 initcall_blacklist=sysfb_init"/' "$grub_file"
  echo "  Added initcall_blacklist=sysfb_init"
  changed=true
fi
grep "GRUB_CMDLINE_LINUX_DEFAULT" "$grub_file" | sed 's/^/  /'

# --- 2. /etc/modprobe.d/vfio.conf ---
echo ""
echo "--- vfio-pci modprobe config ---"

desired_line="options vfio-pci ids=${IDS} disable_vga=1"

if [[ -f "$vfio_conf" ]]; then
  current=$(cat "$vfio_conf")
  if grep -q "disable_vga=1" "$vfio_conf" && grep -q "ids=${IDS}" "$vfio_conf"; then
    echo "  Already configured — no change"
    echo "  $current" | sed 's/^/  /'
  else
    # File exists but needs updating — replace the options vfio-pci line
    if grep -q "^options vfio-pci" "$vfio_conf"; then
      sed -i "s|^options vfio-pci.*|${desired_line}|" "$vfio_conf"
    else
      echo "$desired_line" >> "$vfio_conf"
    fi
    echo "  Updated"
    sed 's/^/  /' "$vfio_conf"
    changed=true
  fi
else
  echo "$desired_line" > "$vfio_conf"
  echo "  Created $vfio_conf"
  sed 's/^/  /' "$vfio_conf"
  changed=true
fi

# --- 3. Apply changes ---
if $changed; then
  echo ""
  echo "--- Applying changes ---"
  echo "  Running update-grub..."
  update-grub 2>&1 | grep -v "^$" | tail -5 | sed 's/^/  /'

  echo "  Running update-initramfs..."
  update-initramfs -u -k all 2>&1 | tail -5 | sed 's/^/  /'

  echo ""
  echo "=== Changes applied. REBOOT REQUIRED for changes to take effect. ==="
  echo "  After reboot, run vfio-check.sh to verify readiness."
else
  echo ""
  echo "=== No changes needed — host is already configured. ==="
  echo "  Run vfio-check.sh to verify full readiness."
fi
