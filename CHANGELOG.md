# Changelog

All notable changes to this NetHunter kernel build for Nothing Phone (1) (`spacewar`).

This file follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/).

Version format: `vMAJOR.MINOR.PATCH` — major bumps on LOS major-version change, minor on kernel-image change, patch on module/docs-only fixes.

---

## [Unreleased]

_(no in-flight changes)_

---

## [v1.1.2] — 2026-04-29

**Bugfix sweep — closes 4 issues found in v1.1.1 post-deployment review.**

Same kernel commit as v1.1.0/v1.1.1 (`88ac9aaa6` — FULL_MON internal Wi-Fi monitor RX).

### Fixed

- `log_buf_len=524288` appended to kernel CMDLINE in `scripts/04-configure.sh` to override bootloader's `log_buf_len=256K`. **Known issue:** `CMDLINE_EXTEND` *prepends* our CMDLINE before bootloader's, so bootloader's value still wins by being later in the parse order. Pstore + nh-logcatd compensate; will revisit in a future release.
- `nh-logcatd` panic-incident filter narrowed to **only** `dmesg-ramoops` (real oops marker). Previous filter triggered on `console-ramoops`, written every boot, generating 4 false-positive incidents per day.
- Removed `magisk --zygisk` CLI call in `nh-collect-logs.sh` — that flag doesn't exist in Magisk 30.7.
- SELinux AVC watcher excludes `shell→shell netlink_route_socket` denials (200/day spam from manual `ip link …` runs in adb shell — not real module issues).

### Changed

- `nh-logcatd`: v3.1 → v3.2

### Documentation

- `docs/ROADMAP.md` rewritten with release-status table and "ABI fragility lessons" section. Documents 4-iteration v1.1.1 build saga + which kernel debug flags break vs work on this build, with kernel-source line refs.

---

## [v1.1.1] — 2026-04-29

**Debug visibility release.** Same kernel commit as v1.1.0. Kernel ABI unchanged from v1.1.0 — vendor modules load identically.

### Added

- `CONFIG_LOG_BUF_SHIFT=19` — 4× larger printk ring (128 KB → 512 KB). _Note: bootloader CMDLINE override partially defeats this; see v1.1.2 known issue._
- `CONFIG_PRINTK_TIME=y` — timestamps on every dmesg line.
- `CONFIG_CMDLINE_EXTEND=y` + custom CMDLINE: `ramoops.record_size=2M`, `console_size=512K`, `ftrace_size=1M`, `pmsg_size=512K`, `panic_print=15`. 4× larger pstore region with separate sub-rings per type.
- `nh-logcatd` v2 → v3.1: 12-layer logging tuned for v1.1.1 ramoops. Logcat 8M → 16M, persistent pool 64M → 128M, storage budget 400M → 600M. New: `/dev/pmsg0` boot marker, Magisk ecosystem snapshot per boot (module versions, status flags, magisk daemon log), SELinux AVC denials watcher (60s polling).

### ABI fragility documented

4 build iterations needed to find ABI-safe debug subset. Documented in `scripts/04-configure.sh:255-310` — `DETECT_HUNG_TASK`, `FUNCTION_TRACER`, `LOCKDEP`, `KASAN`, etc. all break vendor `qca_cld3_qca6750.ko` modversions. Conservative subset (above) is the only safe set without rebuilding vendor `.ko` modules.

---

## [v1.1.0] — 2026-04-29

**FULL_MON for Yupik (WCN6855) — internal Wi-Fi monitor mode now captures full management frames including EAPOL.**

v1.0.0 enabled monitor mode + frame injection but the QCACLD-3.0 driver silently dropped ~94% of management frames, leaving handshake capture impossible without an external USB Wi-Fi adapter. v1.1.0 fixes this with a 3-line patch.

### Kernel

**Kernel SHA:** `88ac9aaa6a0ca79d2748a4fc8d6b536d6ebcb135` (1 commit over v1.0.0's `de989ec`)

```diff
# drivers/staging/qcacld-3.0/configs/default_defconfig
+CONFIG_QCA_SUPPORT_FULL_MON := y

# drivers/staging/qca-wifi-host-cmn/dp/wifi3.0/dp_main.c (in QCA6390/6490/6750 case)
 soc->wlan_cfg_ctx->rxdma1_enable = 0;
+if (cfg_get(soc->ctrl_psoc, CFG_DP_FULL_MON_MODE))
+    dp_config_full_mon_mode((struct cdp_soc_t *)soc, 1);
 break;
```

### Verified metrics on physical Nothing Phone 1

| Metric | v1.0.0 | v1.1.0 | Δ |
|--------|--------|--------|---|
| Beacons (27s, ch5) | 18 | 629 | 35× |
| Probe Response | 2 | 70 | 35× |
| netdev rx_dropped ratio | ~42% | 0% | gone |
| EAPOL (90s natural reconnect) | 0 | 2 | works |
| Authentication frames | 0 | 5 | new |

### Hardware reach

Nothing Phone 1 is the **first WCN6855-class device with verified end-to-end full monitor mode in NetHunter** ([kimocoder LIST_OF_DEVICES.txt](https://github.com/kimocoder/qualcomm_android_monitor_mode) doesn't include this chip).

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
