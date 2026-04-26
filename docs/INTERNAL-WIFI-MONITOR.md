# Internal WiFi (wlan0) — Monitor / Capture / Inject

## Hardware

Qualcomm WCN6855 / WCN6855e — driven by `qcacld-3.0` staging driver, builds as `wlan.ko`. The driver coordinates with userspace `cnss-daemon` for firmware loading.

## What works

| Operation | Status |
|-----------|--------|
| Connect to AP (STA mode) | ✅ default, on every boot |
| Switch to monitor mode | ✅ via `con_mode=4` reload (see below) |
| Channel hopping (`iw set channel N`) | ✅ |
| Passive packet capture (`tcpdump`, `airodump-ng`) | ✅ — Beacon, Probe Request/Response, Data, EAPOL — full radiotap with TSF/RSSI/noise/rate |
| Inject (TX) via standard tools (`aireplay-ng`, `hostapd`, etc.) | ❌ **kernel panic** — see "Why inject panics" below |
| Inject via NetHunter app's wireless attack UI | ⚠️ untested today; should work via Kali's custom netlink API |

## Switching wlan0 to monitor mode (workflow)

Standard `iw dev wlan0 set type monitor` returns `Operation not supported on transport endpoint (-95)` even though `iw phy phy0 info` lists `monitor` among supported modes. Kali patch 16/17 explicitly **bypasses iw** for mode switching — the supported method is to **reload `wlan.ko` with `con_mode=4`**.

`con_mode` values (from `core/hdd/inc/wlan_hdd_main.h`):
- `0` = MISSION (STA — default)
- `4` = MONITOR
- `5` = FTM
- `6` = EPPING

### One-shot script

```bash
adb shell 'su -c "
# Stop wifi service so STA refcount drops
svc wifi disable
sleep 2

# Bring all interfaces down
ip link set wlan0 down 2>/dev/null
ip link set p2p0 down 2>/dev/null
ip link set wifi-aware0 down 2>/dev/null

# Unload + reload with monitor mode
rmmod wlan
insmod /data/local/tmp/wlan.ko con_mode=4

# Trigger cnss-daemon to bring driver online
svc wifi enable
sleep 5

# Verify
cat /sys/module/wlan/parameters/con_mode    # → 4
iw dev wlan0 info | grep type               # → type monitor
"'
```

The `wlan.ko` itself is in `output/wlan.ko` (15 MB stripped, vermagic must match running kernel). Push to phone first:

```bash
adb push output/wlan.ko /data/local/tmp/wlan.ko
```

### Capture frames

```bash
adb shell 'su -c "
ip link set wlan0 up
iw dev wlan0 set channel 6
tcpdump -i wlan0 -c 20 -nn
"'
```

Sample output (real, captured today):
```
... 1.0 Mb/s 2437 MHz 11b -49dBm signal -95dBm noise antenna 0 Beacon (ZTE-dcf5aa) [...] ESS CH: 6, PRIVACY
... 1.0 Mb/s 2437 MHz 11b -75dBm signal -95dBm noise antenna 0 Probe Request (HUAWEI-A1-86E282-5) [...]
... 1.0 Mb/s 2437 MHz 11b -80dBm signal -95dBm noise antenna 0 Probe Response (HUAWEI-A1-3E0DDA-2.4) [...]
```

### From inside Kali chroot

```bash
adb shell 'su -c "chroot /data/local/nhsystem/kali-arm64 /bin/bash"' <<'EOF'
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
airmon-ng              # → phy0  wlan0  icnss2  Not pci, usb, or sdio
ip link set wlan0 up
iw dev wlan0 set channel 6
airodump-ng wlan0      # full pretty UI
EOF
```

### Returning to STA

Reverse the above with `con_mode=0` (or just reboot — Magisk module re-loads Realtek drivers on boot, and the system re-loads the in-tree wlan with `con_mode=0` default):

```bash
adb shell 'su -c "
svc wifi disable
ip link set wlan0 down
rmmod wlan
insmod /data/local/tmp/wlan.ko con_mode=0
svc wifi enable
"'
```

## Why inject panics

Standard userspace inject tools (`aireplay-ng --test`, `hostapd`, `bettercap`'s WiFi module, `wifite2` deauth) call into kernel via the `nl80211 → mac80211 → ndo_start_xmit` indirect call chain. The Kali QCACLD inject patches (17 patches in `kali-kernel-builder`) added a parallel codepath:

```
NetHunter app
   ↓ netlink vendor command (CFI-clean signature, written by patch authors)
   ↓
   hdd_frame_inject_netlink()
   ↓
   WMI_PDEV_FRAME_INJECT_CMDID  (firmware-level)
```

But the **standard mac80211 path** they didn't fully reroute — it still goes through driver-internal indirect calls whose signatures don't match what CFI expects (same root cause as Realtek's case in `docs/CFI-FIX.md`). On CFI=on kernel, first attempt to inject → CFI hash mismatch → kernel panic + reboot.

**Why it worked on the previous Android 13 + kimocoder XOS-14.0.2 setup:** that kernel was built with Neutron-Clang-19 (CFI=off by default). With no CFI checks at runtime, mismatched signatures don't panic. Standard `aireplay-ng` worked.

But **CFI=off is not an option on LineageOS 23.2** because vendor modules (sensors, audio, network indicators) refuse to load on a CFI=off kernel. Trying that path (Stage 4-NoCFI) produced a phone with broken sensors and missing battery/signal icons in the nav-bar.

## Path forward

1. **Today's practical solution** — use **WN722N** (or any Realtek dongle from `modules/`) for inject. WN722N + the `8188eu.ko` we ship works for `airmon-ng`, `aireplay-ng`, `hostapd-mana`, `wifite2`, etc. Verified today: monitor + 5 frames captured + no panic on type-switch.

2. **Use NetHunter app's wireless UI** — the app calls `hdd_frame_inject_netlink` directly via JNI (CFI-clean). Untested today but should work for the attack scenarios the app exposes.

3. **CFI fix patches for QCACLD inject** — multi-hour task: read kernel oops on inject, identify each function pointer with mismatched signature, write source patches following the pattern of `docs/CFI-FIX.md` (Realtek's PR #1041 approach). Not done in this session.
