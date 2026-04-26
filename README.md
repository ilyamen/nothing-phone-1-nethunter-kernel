# Nothing Phone 1 (spacewar) — NetHunter Kernel + External Wi-Fi Drivers

Custom Kali NetHunter kernel for the **Nothing Phone 1 (codename: spacewar / A063)** running **LineageOS 23.2 (Android 16)** + Magisk 30.7. Verified end-to-end: monitor mode + capture on internal *and* external Wi-Fi, packet inject on external Realtek dongles.

> **For the full timeline + bug catalogue + final state, read [docs/BUILD-LOG-2026-04-26.md](docs/BUILD-LOG-2026-04-26.md).**
> **Resuming on a new PC? Read [docs/CONTINUE-ON-NEW-PC.md](docs/CONTINUE-ON-NEW-PC.md).**

## What's in this build

- **Kernel:** `5.4.302-qgki-g192e5b024436-dirty` based on [`kimocoder/android_kernel_lineage_nothing_sm7325`](https://github.com/kimocoder/android_kernel_lineage_nothing_sm7325) branch `nethunter-23.0` (= upstream LOS lineage 5.4.302-qgki + Kali QCACLD inject 17-patch series), built with **AOSP Clang `r536225`** (Clang 19.0.1).
- **Defconfig:** `vendor/lahaina-qgki_defconfig` + `vendor/debugfs.config` (canonical LOS approach).
- **CFI=on + LTO=on** — required for LineageOS 23.2 vendor modules (sensors, audio, network indicators) to load.
- **Realtek CFI signature fix (PR #1041 by GeorgeBannister)** applied to all 3 out-of-tree drivers — required to avoid kernel panic on `iw set type monitor`. See [docs/CFI-FIX.md](docs/CFI-FIX.md).
- **Kali NetHunter QCACLD-3.0 17-patch injection series** applied to internal `wlan.ko`. See [docs/INTERNAL-WIFI-MONITOR.md](docs/INTERNAL-WIFI-MONITOR.md).
- **Deterministic config-match build approach** — modules are built against `Module.symvers` byte-identical to what's running on the phone, so no boot.img reflash needed when only modules change. See `docs/BUILD-LOG-2026-04-26.md` (Bug 13).

## What works

| Sub-system | Status |
|------------|--------|
| Daily phone use (calls, sensors, battery icon, audio) | ✅ |
| Magisk root | ✅ |
| External Realtek drivers auto-load on boot | ✅ via Magisk module |
| `iw set type monitor` on Realtek wlan1 | ✅ no panic |
| `tcpdump`/`airodump-ng` on Realtek wlan1 | ✅ |
| `aireplay-ng` deauth/inject on Realtek wlan1 | ✅ |
| Internal WiFi `wlan0` daily STA mode | ✅ |
| Internal WiFi `wlan0` monitor + capture (via `con_mode=4`) | ✅ |
| Internal WiFi `wlan0` inject via standard `aireplay-ng` | ❌ kernel panic — see [docs/INTERNAL-WIFI-MONITOR.md](docs/INTERNAL-WIFI-MONITOR.md) |
| NetHunter Manager + Store + NHTerm + Kali 2026.1 chroot | ✅ |

## Verified Realtek adapters

| Adapter | Chipset | USB ID | Module | Field-tested |
|---|---|---|---|---|
| TP-Link TL-WN722N v3 | RTL8188EUS | `2357:010c` | `8188eu.ko` | ✅ monitor + inject + capture |
| Asus USB-AC58 | RTL8812BU | `0b05:19aa` | `88x2bu.ko` | ⏳ built, not yet field-tested |
| Mercusys MU-6H | RTL8811CU | `0bda:c811` (after `usb_modeswitch`) | `8821cu.ko` | ⏳ built, not yet field-tested |

## Quick install (assuming clean LOS 23.2 + Magisk on phone)

```bash
# 0. Pull running config from phone (one-time)
adb shell "su -c 'cat /proc/config.gz'" > running-config.gz

# 1. Build kernel + modules
scripts/01-setup-container.sh
scripts/02-clone-sources.sh
scripts/03-apply-patches.sh         # incl. Realtek CFI fix from PR #1041
scripts/04-configure.sh             # uses running-config.gz for deterministic match
scripts/05-build-kernel.sh
scripts/06-build-modules.sh         # Realtek .ko in /work/modules-FINAL/

# 2. Push Realtek modules + install Magisk module (auto-load on boot)
adb push output/realtek-wifi-cfi-fix-v1.0.zip /sdcard/Download/
adb shell "su -c 'magisk --install-module /sdcard/Download/realtek-wifi-cfi-fix-v1.0.zip && \
                  unzip -o /sdcard/Download/realtek-wifi-cfi-fix-v1.0.zip \
                        -d /data/adb/modules/realtek-wifi-cfi-fix -x META-INF/*'"
adb reboot

# 3. (Optional) Install NetHunter app + chroot
adb install installers/NetHunterStore.apk
adb install installers/NetHunter-2026.1.apk
adb shell "am start -n com.offsec.nethunter/.AppNavHomeActivity"
# In app: Allow root → Chroot Manager → Install kalifs-arm64-minimal
```

## Why this build exists

The official Kali NetHunter [devices.yml](https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-devices/-/raw/main/devices.yml) entry for spacewar points to `kimocoder/android_kernel_nothing_sm7325 -b nethunter-stable` — **that repo is 404**, source is gone. The fork at `kimocoder/android_kernel_lineage_nothing_sm7325 -b nethunter-23.0` boot-loops on LOS 23.2 because its base is too old.

Solution: take **upstream LineageOS source** (which has the modern device tree + Android 16 vendor compatibility), apply **Kali's 17-patch QCACLD inject series** via `git am`, apply **PR #1041 CFI fix** to Realtek drivers, build with **AOSP Clang r536225 + CFI=on + LTO=on**.

## Build it yourself

- [docs/BUILD.md](docs/BUILD.md) — original build doc (now points to the docker pipeline).
- [docs/BUILD-LOG-2026-04-26.md](docs/BUILD-LOG-2026-04-26.md) — **comprehensive log with all 18 bugs and fixes**.
- [docs/CFI-FIX.md](docs/CFI-FIX.md) — Realtek PR #1041 explained.
- [docs/INTERNAL-WIFI-MONITOR.md](docs/INTERNAL-WIFI-MONITOR.md) — `con_mode=4` workflow + inject panic root-cause.
- [docs/CONTINUE-ON-NEW-PC.md](docs/CONTINUE-ON-NEW-PC.md) — resume work on a different machine.
- [docs/MERCUSYS-USB-MODESWITCH.md](docs/MERCUSYS-USB-MODESWITCH.md) — getting MU-6H out of CD-ROM mode.
- [docs/FLASH.md](docs/FLASH.md) / [docs/DIAGNOSTICS.md](docs/DIAGNOSTICS.md) — original repo docs.

## Credits

- [@kimocoder](https://github.com/kimocoder) — kernel source + AnyKernel3 + Kali QCACLD-3.0 inject patch series
- [@GeorgeBannister](https://github.com/aircrack-ng/rtl8812au/pull/1041) — CFI signature fix for Realtek (PR #1041)
- [LineageOS](https://github.com/LineageOS/android_kernel_qcom_sm8350) — upstream kernel
- Google AOSP — Clang `r536225` prebuilt toolchain
- [@aircrack-ng](https://github.com/aircrack-ng) — `rtl8188eus`
- [@morrownr](https://github.com/morrownr) — `88x2bu-20210702`, `8821cu-20210916`
- Kali Linux NetHunter team — build infrastructure

## License

GPL-2.0 (kernel and drivers). Configs/scripts in this repo: MIT.
