# artix-bluetooth-audio

Bluetooth audio management scripts for Artix Linux (runit) with TOZO T10 earbuds and TP-Link UB500 dongle.

## Hardware

| Device | Details |
|---|---|
| [TP-Link UB500](https://www.tp-link.com/uk/home-networking/adapter/ub500/) | Bluetooth 5.0 Nano USB Adapter (RTL8761B chipset), permanently installed |
| [TOZO T10](https://www.tozostore.com/products/t10) | True Wireless Earbuds, Bluetooth 5.3, IPX8 waterproof |

## Requirements

- Artix Linux with runit
- PipeWire + WirePlumber
- `bluez`, `bluez-utils`
- `expect` (for fallback pairing)

## Installation

```bash
# 1. Run setup (as root)
sudo bash setup.sh

# 2. Install daily-use scripts
sudo cp bin/earbuds /usr/local/bin/
sudo cp bin/speaker /usr/local/bin/
sudo cp bin/bluetooth-sanity-check /usr/local/bin/
sudo chmod 755 /usr/local/bin/{earbuds,speaker,bluetooth-sanity-check}
```

## Usage

```bash
earbuds               # Connect TOZO T10, switch audio to earbuds
speaker               # Disconnect TOZO T10, switch audio to speakers
bluetooth-sanity-check  # Verify everything is healthy
bash utils/recovery-pair.sh # First-time or recovery pairing
```

## Switching Between Computers

The UB500 dongle is **permanently installed** in one machine. The TOZO T10 is paired to both the Linux machine (via UB500) and a MacBook Pro (via built-in Bluetooth).

To switch:
1. Run `speaker` on the current machine
2. Put earbuds in case
3. Take earbuds out near the other machine
4. Run `earbuds` (Linux) or select from Bluetooth menu (macOS)

## Tested On

- Artix Linux (runit) — kernel 7.0.x
- PipeWire 1.6.x + WirePlumber 0.5.x
- TP-Link UB500 (RTL8761B chipset)
- TOZO T10 (SN: 00T1085A series)

## Known Issues

- After a kernel update, always reboot before using Bluetooth (`uname -r` should match `ls /lib/modules/`)
- macOS aggressively auto-connects to the TOZO — disable Mac Bluetooth before switching to Linux if needed
- First-time pairing requires `recovery-pair.sh` due to TOZO's short pairing window

## Architecture

```
TOZO T10 ←──── Bluetooth ────→ TP-Link UB500
                                      │
                                 BlueZ 5.x
                                      │
                                 WirePlumber
                                      │
                                  PipeWire
                                      │
                               MPD / any app
```

## Files

| File | Purpose |
|---|---|
| `setup.sh` | One-time system setup |
| `bin/earbuds` | Switch audio to TOZO T10 |
| `bin/speaker` | Switch audio to speakers |
| `bin/bluetooth-sanity-check` | Health check |
| `utils/recovery-pair.sh` | First-time/recovery pairing |

## Credits

- Scripts developed with [Claude](https://claude.ai) (Anthropic) over an extensive troubleshooting session covering Bluetooth stack debugging, PipeWire/WirePlumber configuration, kernel module issues, and multi-OS audio switching.
- Hardware tested on HP EliteDesk 800 G1 running Artix Linux.

## License

MIT
