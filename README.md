# Nothing Phone (1) NetHunter — Build & Release

Custom Kali NetHunter kernel + Magisk modules for **Nothing Phone (1)** (codename `spacewar`, model `A063`) running **LineageOS 23.2 (Android 16)**.

## I just want to flash it

→ Download the latest release: [Releases](../../releases/latest)
→ Follow [docs/INSTALL.md](docs/INSTALL.md)

## What you get

- **Custom kernel** with Kali NetHunter QCACLD-3.0 frame injection (Wi-Fi monitor mode + packet inject from internal `wlan0`)
- **3 Realtek USB Wi-Fi drivers** with CFI fix: RTL8188EUS, RTL8812BU, RTL8821CU — work in monitor mode + injection
- **Full NetHunter feature set** in kernel: USBIP, Bluetooth USB Arsenal, BadUSB-ready (HID Gadget configfs), DriveDroid (mass-storage gadget), USB Serial (FTDI/CH341/PL2303/CP210x/cellular modems), USB Ethernet host (RTL8152, AX88179) + gadget (RNDIS/ECM/EEM), DVB-USB-RTL28xxU (RTL-SDR), MAC80211_HWSIM (evil twin)
- **WireGuard VPN** + crypto deps
- **NTFS read+write, CIFS/SMB**
- **L2TPv3, PPP_MULTILINK, TC actions**
- **Persistent logging** with auto-incident-freeze on kernel panic ([nh-logcatd](magisk-modules/nh-logcatd/))

## I want to build it myself

You'll need:
- Linux or WSL2 + Docker (~10 GB free)
- ~6 GB more for AOSP Clang `r547379` (auto-downloaded)
- ~30 minutes per build

```bash
git clone https://github.com/ilyamen/nothing-phone-1-nethunter-kernel
cd nothing-phone-1-nethunter-kernel
scripts/01-setup-container.sh    # Docker container with build deps
scripts/02-clone-sources.sh      # Pulls kernel + AnyKernel + Realtek + toolchain
scripts/03-apply-patches.sh      # Applies Realtek CFI patches
scripts/04-configure.sh          # NH_FEATURES_NET=1 by default
scripts/05-build-kernel.sh       # Builds Image + dtbs + .ko modules
scripts/06-build-modules.sh      # Builds Realtek out-of-tree drivers
scripts/07-package-zip.sh        # AnyKernel3 zip
scripts/08-pack-boot-img.sh      # Repacks stock boot.img with new kernel
scripts/09-build-magisk-modules.sh   # Packs all 8 Magisk module zips
```

To make a GitHub release after building:
```bash
git tag -a v1.1.2 -m 'Release v1.1.2'
scripts/10-make-release.sh v1.1.2
```

Released versions: v1.0.0 (initial), v1.1.0 (FULL_MON internal Wi-Fi RX), v1.1.1 (debug visibility), v1.1.2 (bugfix sweep). See [CHANGELOG.md](CHANGELOG.md) for full history.

Full build documentation in [docs/BUILD.md](docs/BUILD.md). Bug catalogue from initial development in [docs/BUILD-LOG-2026-04-26.md](docs/BUILD-LOG-2026-04-26.md).

## Repo layout

| Dir | What |
|---|---|
| `scripts/` | Build pipeline (01–10) |
| `kernel-pin.env` | Pinned kernel SHA + toolchain version |
| `magisk-modules/` | Source for 8 Magisk modules |
| `realtek-patches/` | CFI fixes for the out-of-tree Realtek USB Wi-Fi drivers |
| `phone-scripts/` | Optional Termux:Widget helpers (run on phone) |
| `docs/` | Build, flash, debug docs |
| `.github/workflows/` | Manual-trigger release workflow |

The kernel source itself is a separate repo:
→ https://github.com/ilyamen/android_kernel_nothing_sm7325_nethunter

## Magisk modules

| Module | Purpose | Required? |
|---|---|---|
| `nh-overlay-base` | NetHunter apps in `/system/priv-app`, F-Droid client + repos, addon.d | recommended |
| `nh-logcatd` | Persistent kernel + userspace logs, auto-freeze panic incidents | recommended |
| `realtek-wifi-cfi-fix` | Realtek USB Wi-Fi drivers + CFI fix | only if using USB Wi-Fi |
| `nh-wifi-adb` | ADB on TCP port 44444 | optional |
| `nh-batch5-vpn` | WireGuard kernel module + crypto deps | optional |
| `nh-batch5-storage` | NTFS, CIFS modules | optional |
| `nh-batch5-net-extras` | USB CDC, PPP, L2TP modules | optional |
| `nh-batch5-tc` | TC actions modules | optional |
| `nh-batch6-usb-serial` | FTDI/CH341/PL2303/CP210x + cellular USB modems | optional |

## Releases

See [CHANGELOG.md](CHANGELOG.md). Releases are cut manually via `scripts/10-make-release.sh` or via the "Build & Release" GitHub Action on this repo (manual trigger).

## License

GPL-2.0 for kernel source and derived `.ko` modules. MIT for the build scripts and configuration files. See [LICENSE](LICENSE) and individual file headers.

## Credits

- [LineageOS](https://lineageos.org/) — base kernel ([android_kernel_nothing_sm7325](https://github.com/LineageOS/android_kernel_nothing_sm7325))
- [Kali Linux NetHunter](https://www.kali.org/docs/nethunter/) — QCACLD-3.0 frame injection patch
- [kimocoder](https://github.com/kimocoder) — pioneering NetHunter for Nothing Phone (1), [AnyKernel3 spacewar branch](https://github.com/kimocoder/AnyKernel3/tree/spacewar)
- [GeorgeBannister](https://github.com/aircrack-ng/rtl8812au/pull/1041) — Realtek CFI fix base
- [aircrack-ng team](https://github.com/aircrack-ng/rtl8188eus) — RTL8188EUS upstream
- [morrownr](https://github.com/morrownr) — RTL8812BU + RTL8821CU upstreams
- [topjohnwu](https://github.com/topjohnwu/Magisk) — Magisk root framework
