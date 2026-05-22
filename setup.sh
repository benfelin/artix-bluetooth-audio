#!/usr/bin/env bash
# setup.sh — One-time Bluetooth audio setup for Artix Linux
# Supports runit and OpenRC
# Run as root: sudo bash setup.sh

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -ne 0 ]] && error "Please run as root: sudo bash setup.sh"

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
REAL_UID=$(id -u "$REAL_USER")

# ── Detect init system ────────────────────────────────────────────────────────
if command -v sv &>/dev/null && [[ -d /run/runit ]]; then
  INIT="runit"
  info "Detected init system: runit"
elif command -v rc-service &>/dev/null; then
  INIT="openrc"
  info "Detected init system: OpenRC"
else
  error "Cannot detect init system — only runit and OpenRC are supported"
fi

# ── 1. Install packages ───────────────────────────────────────────────────────
info "Installing Bluetooth packages..."
pacman -S --needed --noconfirm bluez bluez-utils pipewire pipewire-pulse \
  pipewire-audio wireplumber expect

# Install init-specific package
if [[ "$INIT" == "openrc" ]]; then
  pacman -S --needed --noconfirm bluez-openrc
fi

# ── 2. Enable bluetoothd ──────────────────────────────────────────────────────
info "Enabling bluetoothd..."
case "$INIT" in
  runit)
    if [[ ! -L /run/runit/service/bluetoothd ]]; then
      ln -s /etc/runit/sv/bluetoothd /run/runit/service/bluetoothd
    fi
    sv start bluetoothd || true
    ;;
  openrc)
    rc-update add bluetoothd default 2>/dev/null || true
    rc-service bluetoothd start || true
    ;;
esac

# ── 3. OpenRC-specific: rfkill-unblock service ────────────────────────────────
if [[ "$INIT" == "openrc" ]]; then
  info "Creating rfkill-unblock boot service..."
  cat > /etc/init.d/rfkill-unblock << 'RCEOF'
#!/usr/bin/openrc-run
description="Unblock Bluetooth rfkill"
start() {
    ebegin "Unblocking Bluetooth"
    rfkill unblock bluetooth
    eend $?
}
RCEOF
  chmod +x /etc/init.d/rfkill-unblock
  rc-update add rfkill-unblock boot

  info "Patching bluetoothd init script for rfkill..."
  BLUETOOTHD_INIT="/etc/init.d/bluetoothd"
  if ! grep -q "command_pre_start" "$BLUETOOTHD_INIT"; then
    sed -i '/^command=.*/a command_pre_start() {\n    rfkill unblock bluetooth\n}' \
      "$BLUETOOTHD_INIT"
  fi
  if ! grep -q "rfkill-unblock" "$BLUETOOTHD_INIT"; then
    sed -i 's/need dbus localmount hostname/need dbus localmount hostname rfkill-unblock/' \
      "$BLUETOOTHD_INIT"
  fi

  info "Adding udev rfkill rule..."
  cat > /etc/udev/rules.d/50-bluetooth.rules << 'UDEVEOF'
ACTION=="add", SUBSYSTEM=="rfkill", ATTR{type}=="bluetooth", ATTR{soft}="0"
UDEVEOF

  info "Setting DBUS_SESSION_BUS_ADDRESS in ~/.xprofile..."
  XPROFILE="$REAL_HOME/.xprofile"
  if ! grep -q "DBUS_SESSION_BUS_ADDRESS" "$XPROFILE" 2>/dev/null; then
    sed -i "1a export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$REAL_UID/bus\nexport XDG_RUNTIME_DIR=/run/user/$REAL_UID" \
      "$XPROFILE"
  fi

  info "Disabling WirePlumber logind (required for xdm/VNC)..."
  mkdir -p "$REAL_HOME/.config/wireplumber/wireplumber.conf.d"
  cat > "$REAL_HOME/.config/wireplumber/wireplumber.conf.d/disable-logind.conf" << 'WPEOF'
wireplumber.profiles = {
  main = {
    support.logind = disabled
  }
}
WPEOF
  chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/wireplumber"

  info "Setting PipeWire/WirePlumber environment variables..."
  mkdir -p "$REAL_HOME/.config/rc/conf.d"
  for svc in pipewire pipewire-pulse wireplumber; do
    cat > "$REAL_HOME/.config/rc/conf.d/$svc" << CONFEOF
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$REAL_UID/bus
export DISPLAY=:0
export XDG_RUNTIME_DIR=/run/user/$REAL_UID
CONFEOF
  done
  chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/rc"
fi

# ── 4. BlueZ main.conf ───────────────────────────────────────────────────────
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

# ── 5. sudoers ───────────────────────────────────────────────────────────────
info "Adding sudoers rules..."
cat > /etc/sudoers.d/bluetooth-tools << SUDOEOF
$REAL_USER ALL=(ALL) NOPASSWD: /usr/bin/btmgmt
$REAL_USER ALL=(ALL) NOPASSWD: /usr/sbin/rfkill
SUDOEOF
chmod 440 /etc/sudoers.d/bluetooth-tools

# ── 6. Restart services ───────────────────────────────────────────────────────
info "Restarting services..."
case "$INIT" in
  runit)
    sv restart bluetoothd
    ;;
  openrc)
    rc-service rfkill-unblock start
    rc-service bluetoothd restart
    ;;
esac

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Setup complete! (init: $INIT)${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Next steps:"
echo "  1. Install daily scripts:"
echo "     sudo cp bin/earbuds bin/speaker bin/bluetooth-sanity-check /usr/local/bin/"
echo "     sudo chmod 755 /usr/local/bin/{earbuds,speaker,bluetooth-sanity-check}"
echo "  2. First-time pairing:"
echo "     bash utils/tozo-pair.sh"
echo ""
