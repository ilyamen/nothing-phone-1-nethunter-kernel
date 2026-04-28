# Changelog

All notable changes to this NetHunter kernel build for Nothing Phone (1) (`spacewar`).

This file follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/).

Version format: `vMAJOR.MINOR.PATCH` — major bumps on LOS major-version change, minor on kernel-image change, patch on module/docs-only fixes.

---

## [Unreleased]

_(no in-flight changes)_

---

## [v1.0.0] — 2026-04-28

**Initial public release.**

**Kernel SHA:** `de989ec045cf404f7dcd3a5dd819d8e6ea291f3a` (tip of `nethunter-23.2` after CI smoke-test workflow added; kernel-source byte-identical to `7bf1f200bd00e04ccb4b6e707df597303b5981bd`)
**LineageOS base:** `lineage-23.2`
**Toolchain:** AOSP Clang `r547379` (Clang 19.0.1)

### Added

- Kali NetHunter QCACLD-3.0 frame injection patch — 14 commits over LOS lineage-23.2 (full Kali patch series, broken into individual commits for transparency)
- Realtek out-of-tree USB Wi-Fi drivers with CFI fix:
  - RTL8188EUS (TP-Link WN722N v3, etc.)
  - RTL8812BU (Asus USB-AC58, etc.)
  - RTL8821CU (Mercusys MU-6H, etc.)
  - Custom `xmit_tasklet` CFI signature fix for 88x2bu and 8188eu (PR #1041 missed these)
- 9 Magisk modules:
  - `nh-overlay-base` v1.1 — NetHunter apps in /system/priv-app + F-Droid + F-Droid Privileged Extension. Auto-adds NetHunter Store + IzzyOnDroid F-Droid repos on first PIN unlock via `fdroidrepos://` intents (replaces deprecated NetHunter Store).
  - `nh-logcatd` v2 — 8-layer persistent logging with auto-incident-freeze on kernel panic, 32 MB rotating logcat, 24 hourly dmesg snapshots, 50 boot dmesg history, 400 MB hard cap
  - `realtek-wifi-cfi-fix` — auto-loads 3 Realtek drivers on boot
  - `nh-wifi-adb` — ADB over TCP port 44444
  - `nh-batch5-vpn` — WireGuard + 5 crypto deps
  - `nh-batch5-storage` — NTFS, CIFS, dns_resolver
  - `nh-batch5-net-extras` — USB CDC NCM/MBIM/EEM, USB WDM, PPP async/sync, L2TP IP/ETH
  - `nh-batch5-tc` — TC actions (act_bpf, act_mirred, act_nat, act_pedit)
  - `nh-batch6-usb-serial` — 12 USB Serial drivers (FTDI, CH341, PL2303, CP210x, OPTION, qcserial, cdc-acm, huawei_cdc_ncm, qmi_wwan, usblp, usb_wwan, usbserial framework)
- Kernel feature flags (in `scripts/04-configure.sh`, all default ON):
  - **Batch 4-fixed:** USBIP, BT_HCIBTUSB, WLAN_VENDOR_ATH/BROADCOM, MT76/RT2X00/ATH9K_HTC modules, MAC80211_HWSIM, HID_PID, NFSD V3/V4, NETFILTER_XT_MATCH_MULTIPORT, PACKET/UNIX/INET_DIAG, LIB80211 + WEP/CCMP/TKIP
  - **Batch 5:** WIREGUARD + crypto, USB_NET_CDC_NCM/MBIM/EEM, USB_WDM, L2TP_V3, PPP_MULTILINK/FILTER, NET_ACT_*, NTFS_FS+RW, CIFS+UPCALL/XATTR/POSIX/DFS_UPCALL
  - **Batch 6:** USB_SERIAL family, USB_ACM, cellular USB modems, USB_AUDIO, USB_PRINTER host
  - **Batch 7:** USB Gadget MTP/PTP/UVC/PRINTER + RNDIS/ECM/EEM (USB-Ethernet attack vectors)
  - **DVB-USB-RTL28XXU** for RTL-SDR via USB DVB-T sticks
- Verified `pstore` kernel panic capture with auto-freeze (testing via `echo c > /proc/sysrq-trigger` confirmed `console-ramoops-0` + `pmsg-ramoops-0` survive panic→reboot cycle)
- Bug 16 fix: `aireplay-ng wlan0` panic resolved via Kali patches 03/04/08/10/16 (asynchronous synchronization)
- Documented GKI vendor ABI rules: which kernel config flags must NOT be enabled to keep LOS vendor `.ko`s loading (CAN, NETFILTER_NETLINK_ACCT, CFG80211_WEXT, MAC80211_MESH — all add fields to `struct net` / `struct sk_buff` / `struct wiphy`)

### Build infrastructure

- Pinned kernel SHA via `kernel-pin.env` for reproducible builds
- Manual local release script: `scripts/10-make-release.sh`
- Workflow_dispatch GitHub Action: `.github/workflows/release.yml` (CI release, manual trigger)

### Known issues

- Internal Wi-Fi (`wlan0`) packet inject works via Kali QCACLD patches but `aireplay-ng wlan0` is the verified path; some `iw`-only direct-inject sequences still cause `htt_h2t_full_mon_cfg_msg` warnings (cosmetic, no functional impact).
- USB Gadget RNDIS/ECM works in parallel with Qualcomm `USB_F_GSI` but real-world host-attack scenarios (laptop seeing phone as Ethernet adapter) untested in field.
- DVB-USB RTL28xxU built into kernel; RTL-SDR userspace via Kali chroot (`apt install rtl-sdr`).

[Unreleased]: https://github.com/ilyamen/nothing-phone-1-nethunter-kernel/compare/v1.0.0...HEAD
[v1.0.0]: https://github.com/ilyamen/nothing-phone-1-nethunter-kernel/releases/tag/v1.0.0
