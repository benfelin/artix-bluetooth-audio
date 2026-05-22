#!/usr/bin/env bash
# tozo-pair.sh — Pair TOZO T10 on Artix OpenRC
# Run from X session terminal (VNC or local)

MAC="94:4B:F8:01:52:02"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  TOZO T10 Pairing Script"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── 1. Unblock and power on ───────────────────────────────────────────────────
echo "[1/5] Unblocking and powering on Bluetooth..."
sudo rfkill unblock bluetooth
bluetoothctl power on
sleep 2

# ── 2. Remove stale pairing ───────────────────────────────────────────────────
echo "[2/5] Removing any stale pairing..."
bluetoothctl remove "$MAC" 2>/dev/null || true
sleep 1

# ── 3. Prompt user ────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  👉 Put TOZO T10 in pairing mode NOW:"
echo "     - Put both earbuds in the case"
echo "     - Take them out"
echo "     - Wait for earbud to flash red/blue"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Waiting 15 seconds for pairing mode..."
sleep 15

# ── 4. Scan using btmgmt ──────────────────────────────────────────────────────
echo "[3/5] Scanning for TOZO T10..."
FOUND=false
for attempt in {1..3}; do
  SCAN=$(sudo btmgmt find 2>/dev/null)
  if echo "$SCAN" | grep -q "$MAC\|TOZO"; then
    echo "✔ TOZO T10 found!"
    FOUND=true
    break
  fi
  echo "Not found yet, retrying ($attempt/3)..."
  sleep 5
done

if [[ "$FOUND" != "true" ]]; then
  echo "✘ TOZO T10 not found — is it in pairing mode?"
  exit 1
fi

# ── 5. Pair using expect — scan on, pair WITHOUT stopping scan first ──────────
echo "[4/5] Pairing via bluetoothctl..."
RESULT=$(expect << EXPEOF
set timeout 40
spawn bluetoothctl
expect "#"
send "agent on\r"
expect "#"
send "default-agent\r"
expect "#"
send "scan on\r"
expect "TOZO"
send "pair $MAC\r"
expect -re "(successful|not available|Failed|Rejected)"
send "trust $MAC\r"
expect "#"
send "scan off\r"
expect "#"
send "connect $MAC\r"
expect -re "(successful|not available|Failed)"
send "exit\r"
expect eof
EXPEOF
)
echo "$RESULT"

# ── 6. Set up audio ───────────────────────────────────────────────────────────
echo "[5/5] Setting up audio..."
sleep 3

if pactl list sinks short 2>/dev/null | grep -q "bluez_output"; then
  pactl set-card-profile "bluez_card.${MAC//:/_}" a2dp-sink 2>/dev/null || true
  sleep 1
  pactl set-default-sink "bluez_output.${MAC//:/_}.1"
  paplay /usr/share/sounds/alsa/Front_Center.wav 2>/dev/null || true
  echo ""
  echo "✔ TOZO T10 paired and audio set to A2DP!"
else
  echo ""
  if echo "$RESULT" | grep -q "Connection successful\|Pairing successful"; then
    echo "✔ Paired successfully! Run 'earbuds' to complete audio setup."
  else
    echo "✘ Pairing may have failed. Check output above."
  fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bluetoothctl info "$MAC" 2>/dev/null | grep -E "Name|Paired|Trusted|Connected"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
