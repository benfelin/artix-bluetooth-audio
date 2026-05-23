#!/usr/bin/env bash
# setup.sh — One-time Bluetooth audio setup for Artix Linux (runit)
# Run as root: sudo bash setup.sh

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -ne 0 ]] && error "Please run as root: sudo bash setup.sh"

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# ── 1. Install packages ───────────────────────────────────────────────────────
info "Installing Bluetooth packages..."
pacman -S --needed --noconfirm bluez bluez-utils pipewire pipewire-pulse \
  pipewire-audio wireplumber expect

# ── 2. Enable bluetoothd ──────────────────────────────────────────────────────
info "Enabling bluetoothd..."
if [[ ! -L /run/runit/service/bluetoothd ]]; then
  ln -s /etc/runit/sv/bluetoothd /run/runit/service/bluetoothd
fi
sv start bluetoothd || true

# ── 3. BlueZ main.conf ───────────────────────────────────────────────────────
info "Configuring BlueZ..."
BLUEZ_CONF="/etc/bluetooth/main.conf"
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

# ── 4. sudoers ───────────────────────────────────────────────────────────────
info "Adding sudoers rules..."
cat > /etc/sudoers.d/bluetooth-tools << SUDOEOF
$REAL_USER ALL=(ALL) NOPASSWD: /usr/bin/btmgmt
$REAL_USER ALL=(ALL) NOPASSWD: /usr/sbin/rfkill
SUDOEOF
chmod 440 /etc/sudoers.d/bluetooth-tools

# ── 5. Restart services ───────────────────────────────────────────────────────
info "Restarting services..."
sv restart bluetoothd

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Setup complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Next steps:"
echo "  1. Install daily scripts:"
echo "     sudo cp bin/earbuds bin/speaker bin/bluetooth-sanity-check /usr/local/bin/"
echo "     sudo chmod 755 /usr/local/bin/{earbuds,speaker,bluetooth-sanity-check}"
echo "  2. First-time pairing:"
echo "     bash utils/tozo-pair.sh"
echo ""
