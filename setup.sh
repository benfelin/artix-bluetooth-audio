#!/usr/bin/env bash
# setup.sh — One-time Bluetooth audio setup for Artix Linux (runit)
# Run as root: sudo bash setup.sh
# Use --dry-run to preview actions without making changes

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
dryrun()  { echo -e "${CYAN}[DRY-RUN]${NC} $*"; }

# ── Dry-run mode ──────────────────────────────────────────────────────────────
DRY=false
[[ "${1:-}" == "--dry-run" ]] && DRY=true

run() {
  if $DRY; then
    dryrun "$*"
  else
    eval "$*"
  fi
}

if $DRY; then
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}  DRY-RUN MODE — no changes will be made${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
fi

[[ $EUID -ne 0 ]] && ! $DRY && error "Please run as root: sudo bash setup.sh"

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# ── 1. Install packages ───────────────────────────────────────────────────────
info "Installing Bluetooth packages..."
run "pacman -S --needed --noconfirm bluez bluez-utils pipewire pipewire-pulse pipewire-audio wireplumber expect"

# ── 2. Enable bluetoothd ──────────────────────────────────────────────────────
info "Enabling bluetoothd via runit..."
if $DRY; then
  dryrun "ln -s /etc/runit/sv/bluetoothd /run/runit/service/bluetoothd (if not already linked)"
  dryrun "sv start bluetoothd"
else
  if [[ ! -L /run/runit/service/bluetoothd ]]; then
    ln -s /etc/runit/sv/bluetoothd /run/runit/service/bluetoothd
  else
    info "bluetoothd already enabled — skipping"
  fi
  sv start bluetoothd || true
fi

# ── 3. BlueZ main.conf ───────────────────────────────────────────────────────
info "Configuring BlueZ main.conf..."
BLUEZ_CONF="/etc/bluetooth/main.conf"
if $DRY; then
  dryrun "Add AutoEnable=true under [Policy] in $BLUEZ_CONF (if missing)"
  dryrun "Add FastConnectable=true under [General] in $BLUEZ_CONF (if missing)"
else
  if grep -q "^\[Policy\]" "$BLUEZ_CONF" 2>/dev/null; then
    grep -q "^AutoEnable" "$BLUEZ_CONF" || \
      sed -i '/^\[Policy\]/a AutoEnable=true' "$BLUEZ_CONF"
  else
    echo -e "\n[Policy]\nAutoEnable=true" >> "$BLUEZ_CONF"
  fi
  if grep -q "^\[General\]" "$BLUEZ_CONF" 2>/dev/null; then
    grep -q "^FastConnectable" "$BLUEZ_CONF" || \
      sed -i '/^\[General\]/a FastConnectable=true' "$BLUEZ_CONF"
  else
    echo -e "\n[General]\nFastConnectable=true" >> "$BLUEZ_CONF"
  fi
fi

# ── 4. sudoers ───────────────────────────────────────────────────────────────
info "Adding sudoers rules for btmgmt and rfkill..."
if $DRY; then
  dryrun "Write /etc/sudoers.d/bluetooth-tools:"
  dryrun "  $REAL_USER ALL=(ALL) NOPASSWD: /usr/bin/btmgmt"
  dryrun "  $REAL_USER ALL=(ALL) NOPASSWD: /usr/sbin/rfkill"
else
  cat > /etc/sudoers.d/bluetooth-tools << SUDOEOF
$REAL_USER ALL=(ALL) NOPASSWD: /usr/bin/btmgmt
$REAL_USER ALL=(ALL) NOPASSWD: /usr/sbin/rfkill
SUDOEOF
  chmod 440 /etc/sudoers.d/bluetooth-tools
fi

# ── 5. Restart services ───────────────────────────────────────────────────────
info "Restarting bluetoothd..."
run "sv restart bluetoothd"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if $DRY; then
  echo -e "${CYAN}  Dry-run complete — no changes made${NC}"
else
  echo -e "${GREEN}  Setup complete!${NC}"
fi
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Next steps:"
echo "  1. Install daily scripts:"
echo "     sudo cp bin/earbuds bin/speaker bin/bluetooth-sanity-check /usr/local/bin/"
echo "     sudo chmod 755 /usr/local/bin/{earbuds,speaker,bluetooth-sanity-check}"
echo "  2. First-time pairing:"
echo "     bash utils/recovery-pair.sh"
echo ""
