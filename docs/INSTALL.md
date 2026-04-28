# Installation Guide — Nothing Phone (1) NetHunter

End-user instructions for installing this NetHunter kernel + modules + apps on a stock Nothing Phone (1).

> **Time required:** ~45 min if everything goes smoothly, ~90 min including LineageOS install.
> **Risk:** All steps are reversible via `fastboot`. Only Phase 0 (bootloader unlock) wipes user data.

---

## What you need

### Hardware
- Nothing Phone (1), model **A063** (codename **`spacewar`**)
- USB-C cable
- PC with **adb** + **fastboot** installed (see [Android SDK Platform Tools](https://developer.android.com/tools/releases/platform-tools))

### Files (download from this repo's [Releases](../../../releases/latest))
- `spacewar-nethunter-kernel-vX.Y.Z-boot.img` — kernel boot image
- `spacewar-nethunter-modules-vX.Y.Z.tar.gz` — all 8 Magisk module zips bundled (or pick individual ones)
- `checksums.txt` — SHA-256 verification

### External downloads (one-time)
- **LineageOS 23.2 for spacewar:** https://wiki.lineageos.org/devices/spacewar/install
- **Magisk v30.x APK:** https://github.com/topjohnwu/Magisk/releases/latest

---

## Phase 0 — Stock LineageOS 23.2 + Magisk root (one-time)

If you already have a stock-rooted LOS 23.2 setup, skip to [Phase 1](#phase-1--install-our-nethunter-kernel).

### 0.1 — Unlock bootloader

This **wipes all data** on the phone. Make a backup first if needed.

```bash
adb reboot bootloader
fastboot flashing unlock
# On the phone screen: press Volume Up to confirm "Unlock the bootloader"
# Phone reboots back to bootloader
```

### 0.2 — Install LineageOS 23.2

Follow the [official LineageOS install guide](https://wiki.lineageos.org/devices/spacewar/install). Summary:

```bash
# Download lineage-23.2-XXXXX-nightly-spacewar-signed.zip
# Download lineage-23.2-...-recovery-spacewar.img

# Boot LOS recovery
fastboot flash boot_a lineage-23.2-...-recovery-spacewar.img
fastboot flash boot_b lineage-23.2-...-recovery-spacewar.img
fastboot reboot recovery

# In recovery: Apply update → Apply from ADB
adb sideload lineage-23.2-XXXXX-nightly-spacewar-signed.zip

# Reboot
# Complete first-boot setup (skip Google sign-in for cleanliness if you want)
```

### 0.3 — Install Magisk root

```bash
# Pull stock LOS boot.img for Magisk to patch
adb reboot bootloader
fastboot getvar current-slot   # remember which slot you're on (a or b)
# Boot recovery temporarily (does not flash anything):
fastboot boot lineage-23.2-...-recovery-spacewar.img
# In recovery: ADB sideload, but we need the boot.img to patch.
# Easier path:
fastboot reboot
# Now boot regular LOS, then:

adb push Magisk-v30.x.apk /sdcard/Download/
adb install /sdcard/Download/Magisk-v30.x.apk

# Open Magisk app on phone:
#   - Tap "Install" → "Select and Patch a File"
#   - Pick the LOS boot.img (you can extract it from the LOS zip:
#     unzip lineage-23.2-XXX.zip 'images/boot.img' -d /tmp/los/)
# Magisk creates magisk_patched-XXX.img on /sdcard/Download/

adb pull /sdcard/Download/magisk_patched-XXX.img
adb reboot bootloader
fastboot flash boot_a magisk_patched-XXX.img
# Also slot b for safety:
fastboot flash boot_b magisk_patched-XXX.img
fastboot reboot
```

After reboot, open the Magisk app — it should show "Installed (vXX.X)" and your phone is rooted.

---

## Phase 1 — Install our NetHunter kernel

This is where our work starts. There are two paths — pick one.

### Path A — Patch our boot.img through Magisk (preserves root, recommended)

This is the canonical Magisk-aware kernel install: Magisk takes our `nethunter-kernel-boot.img`, injects its root daemon into the ramdisk, and produces a `magisk_patched-XXX.img` that has BOTH the NetHunter kernel AND root. After flashing it, the phone boots with our kernel + Magisk root, and Magisk modules can run.

```bash
# 1. Push our kernel boot.img to phone
adb push spacewar-nethunter-kernel-vX.Y.Z-boot.img /sdcard/Download/

# 2. Open Magisk app on phone:
#    - Tap "Install" → "Select and Patch a File"
#    - Pick spacewar-nethunter-kernel-vX.Y.Z-boot.img
# Magisk creates magisk_patched-XXX.img with our kernel + root daemon.

# 3. Pull the patched image, flash via fastboot
adb pull /sdcard/Download/magisk_patched-XXX.img
adb reboot bootloader
fastboot flash boot_a magisk_patched-XXX.img
fastboot reboot
```

Phone reboots. After ~15 sec you should see Android home screen as usual. Open Magisk app — confirm "Installed", root works.

### Path B — Direct fastboot flash (no Magisk pre-patching)

If you want to flash the raw kernel without keeping root, skip the Magisk patch step:

```bash
adb reboot bootloader
fastboot flash boot_a spacewar-nethunter-kernel-vX.Y.Z-boot.img
fastboot reboot
```

⚠ **This loses Magisk root** — you'd need to re-run Magisk's patch+flash on this kernel afterward, or install Magisk modules won't work. For most users, **Path A is what you want.**

### Verify the kernel

```bash
adb shell uname -r
# Should print: 5.4.302-qgki-gXXXXXXXX-dirty
# Anything matching that pattern means our kernel is running.
```

---

## Phase 2 — Install Magisk modules

Each module is independent — install only the ones you need.

### Recommended for everyone

| Module | Why |
|---|---|
| **`nh-overlay-base.zip`** | NetHunter app + Terminal + KeX + F-Droid + NetHunter F-Droid repo as system priv-apps. Without this you'll need to install each apk separately. |
| **`nh-logcatd.zip`** | Persistent kernel + userspace logs, auto-freezes panic snapshots — invaluable when something breaks in field use |

### Install procedure (per module)

```bash
adb push <module-name>.zip /sdcard/Download/
# On phone: open Magisk app → Modules → Install from storage → pick zip
```

Repeat for each `.zip` you want. Then **reboot** (in Magisk app, "Restart" button at bottom).

### Optional modules — pick only what you need

| Module | When to install |
|---|---|
| `realtek-wifi-cfi-fix.zip` | If you use external Realtek USB Wi-Fi adapters (RTL8188EUS, RTL8812BU, RTL8821CU) for monitor mode + injection |
| `nh-wifi-adb.zip` | If you want ADB over TCP port 44444 (handy for headless work, just `adb connect <phone-ip>:44444`) |
| `nh-batch5-vpn.zip` | If you'll use WireGuard. Loads `wireguard.ko` + crypto deps at boot. |
| `nh-batch5-storage.zip` | If you'll mount NTFS USB drives or CIFS/SMB shares. |
| `nh-batch5-net-extras.zip` | If you'll plug in cellular USB modems (Huawei NCM, QMI WWAN), use PPP, or L2TP IP/Ethernet. |
| `nh-batch5-tc.zip` | If you're a TC (traffic control) user — fakeAP, redsocks, BPF traffic shaping. Niche. |
| `nh-batch6-usb-serial.zip` | If you'll plug in USB-UART adapters (FTDI, CH341, PL2303, CP210x), Arduino, USB modems. |

After installing the modules you want, reboot once.

---

## Phase 3 — First-boot verification

```bash
# All kernel modules loaded?
adb shell 'su -c lsmod' | wc -l   # expect 70+ modules

# Internet works?
adb shell 'su -c "ping -c 3 -I wlan0 8.8.8.8"'

# NetHunter apps installed (after nh-overlay-base)?
adb shell 'pm list packages | grep -i nethunter'
# Should show com.offsec.nethunter, .store, nhterm, .kex, store.privileged

# F-Droid working with NetHunter repo?
# Open F-Droid on phone — check Settings → Repositories — should list:
#   • F-Droid (default)
#   • F-Droid Archive (default)
#   • NetHunter Store
#   • IzzyOnDroid
```

---

## Phase 4 — Optional: Kali Linux chroot

If you want the full Kali Linux environment (apt install Wireshark, Burp Suite, hashcat, all the tools):

1. Open **NetHunter** app on phone
2. Tap **Chroot Manager** (or "Kali Chroot" — depends on app version)
3. Tap **Download** → pick **Kali ARM64 Full**
4. Wait ~10 minutes (downloads ~1.5 GB rootfs, unpacks to `/data/local/nhsystem/kali-arm64/`)
5. Once installed, **NetHunter Terminal → Kali shell** drops you into the chroot

From there `apt update && apt install <whatever>`. Network through the phone's WiFi/Ethernet. X11 GUI tools through **NetHunter KeX** app (VNC client).

---

## Troubleshooting

### After flashing kernel, phone doesn't boot

Boot loops on boot animation? Black screen?

```bash
# Boot back to fastboot (hold Vol-Down + Power on dead phone, releasing Power when bootloader logo appears)
fastboot devices

# Re-flash stock LOS boot.img to recover:
fastboot flash boot_a lineage-stock-boot.img

# OR boot into LOS recovery and re-flash:
fastboot reboot recovery
```

### Wi-Fi disabled / "no network connection"

Possible cause: a Magisk module that you installed has a kernel-level conflict.

```bash
# Boot into Magisk safe mode: hold Vol-Down for ~5 sec right after bootloader logo passes.
# Magisk will boot with all modules disabled.
# Open Magisk → toggle off the suspect module(s) → reboot normally.
```

### `nh-logcatd` says "tarball is empty" when collecting logs

Phone is still in FBE-locked state (PIN not entered post-boot). The script falls back to `/data/local/tmp/` which is always accessible. Pull from there:

```bash
adb shell 'su -c "ls -t /data/local/tmp/nh-logs-*.tar.gz | head -1"'
adb pull /data/local/tmp/nh-logs-XXXXXXXX.tar.gz
```

### `adb` doesn't see the phone

- Make sure USB debugging is enabled (Settings → Developer options).
- After flashing, the phone may briefly drop ADB during first boot. Wait ~30 sec and retry.
- For wireless ADB (TCP :44444 from `nh-wifi-adb` module): `adb connect <phone-ip>:44444`

### Reverting completely back to stock LOS

```bash
fastboot flash boot_a lineage-stock-boot.img   # back to LOS without our kernel
adb shell 'su -c "magisk --remove-modules"'    # uninstall all Magisk modules
# Reboot
```

To go fully unrooted: re-flash LOS without Magisk patching, then `fastboot flashing lock` (warning: relocking after running custom kernels can brick — research before doing this).

---

## Channels for help

- This repo's [Issues](../../../issues)
- [XDA Forums Nothing Phone 1](https://xdaforums.com/f/nothing-phone-1.12585/)
- [4PDA Nothing Phone 1 thread](https://4pda.to/forum/index.php?showtopic=1052523)
- [Kali NetHunter docs](https://www.kali.org/docs/nethunter/)
