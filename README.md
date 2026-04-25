# Nothing Phone 1 (spacewar) — NetHunter Kernel + External Wi-Fi Drivers

Custom Kali NetHunter kernel for the **Nothing Phone 1 (codename: spacewar)** with working **out-of-tree Realtek Wi-Fi drivers** and **monitor mode + injection** verified end-to-end.

## What's in this build

- **Kernel:** `5.4.281-NetHunter` based on `kimocoder/kernel_nothing_sm7325` branch `XOS-14.0.2`, built with **Neutron Clang 19** (kernel-tuned LLVM toolchain).
- **CFI disabled** (`CONFIG_CFI_CLANG=n`) — this is the critical fix for monitor mode crashes on out-of-tree Realtek drivers.
- **NetHunter feature set parity with official Kali NetHunter spacewar kernel** (HID, BadUSB, DriveDroid, Mass Storage, RNDIS via GSI, Bluetooth Arsenal, QCACLD-3.0 internal Wi-Fi monitor + injection, all USB gadgets).
- **3 external Realtek Wi-Fi drivers as `.ko` modules** for adapters not covered by in-kernel drivers.
- Plus `EXFAT_FS=y` for parity with official Kali kernel.

## Verified working adapters (monitor mode + packet capture)

| Adapter | Chipset | USB ID | Module | Notes |
|---|---|---|---|---|
| TP-Link TL-WN722N v3 | RTL8188EUS | `2357:010c` | `8188eu.ko` | 2.4 GHz only |
| Asus USB-AC58 | RTL8812BU | `0b05:19aa` | `88x2bu.ko` | 2.4 + 5 GHz |
| Mercusys MU-6H | RTL8811CU | `0bda:c811` *(after USB mode switch)* | `8821cu.ko` | 2.4 + 5 GHz, requires `usb_modeswitch` first ([details](docs/MERCUSYS-USB-MODESWITCH.md)) |

Plus the **internal Wi-Fi (Qualcomm QCACLD)** with built-in monitor mode and injection (NetHunter patches included by source).

## Quick install

1. Download the latest release `spacewar-nethunter-vN-FINAL.zip` from [Releases](../../releases).
2. **Backup your current `boot_a` and `boot_b`** via fastboot or TWRP first. Recovery if anything goes wrong:
   ```
   fastboot flash boot_a backup_boot_a.img
   fastboot flash boot_b backup_boot_b.img
   ```
3. On phone: **Franco Kernel Manager → Flasher → select the zip → Flash → Reboot**.

Magisk root is preserved — AnyKernel3 keeps the existing ramdisk.

## Why this kernel exists

The official Kali NetHunter kernel for spacewar:
- Only ships for Android 14 (and the Nothing Phone 1's official Android 14 / AOSPA Uvite isn't always smooth).
- Doesn't include drivers for `RTL8812BU` or `RTL8811CU` chipsets (the in-tree `88XXau` only handles RTL8812**AU**, not BU).
- Has `CFI_CLANG=y` which causes a kernel panic when switching out-of-tree Realtek drivers to monitor mode.

The popular `cr4sh@parrot` build (`5.4.256-NetHunter`) that many spacewar users run works because it has CFI disabled — but ships no external Wi-Fi drivers and no source is published.

This build combines:
- Official Kali NetHunter feature set (HID/BadUSB/QCACLD monitor/injection/all gadgets)
- + The CFI-off pragmatism that makes external Realtek drivers actually work
- + Three pre-built drivers for adapters most likely to be found in a NetHunter pentester's bag
- + Reproducible build via Docker (everything documented)

## Build it yourself

See [docs/BUILD.md](docs/BUILD.md). Whole flow is dockerised — host needs only Docker.

## Diagnostic story

The full debugging journey (X86-by-mistake configs, OrangeFox-not-Android boot.img backup, kernel-panic-during-monitor-mode root-caused to CFI, etc.) is in [docs/DIAGNOSTICS.md](docs/DIAGNOSTICS.md). Useful if you're debugging similar issues.

## Credits

- [@kimocoder](https://github.com/kimocoder) — `kernel_nothing_sm7325` source and the NetHunter QCACLD-3.0 injection patch series.
- [@Neutron-Toolchains](https://github.com/Neutron-Toolchains) — kernel-tuned Clang 19 toolchain.
- [@aircrack-ng](https://github.com/aircrack-ng) — `rtl8188eus` driver with monitor mode.
- [@morrownr](https://github.com/morrownr) — `88x2bu-20210702` and `8821cu-20210916` drivers.
- Kali Linux NetHunter team — kernel build infrastructure.

## License

GPL-2.0 (kernel and drivers). Configs/scripts in this repo: MIT.
