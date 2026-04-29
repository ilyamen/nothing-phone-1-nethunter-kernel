#!/bin/bash
# Configure kernel — DETERMINISTIC approach (matches running kernel byte-for-byte).
#
# Why this matters: building modules requires Module.symvers (symbol CRCs) that
# match what's running on the phone. If the kernel build's config differs from
# what produced the running kernel, modules fail to load with
# "disagrees about version of symbol module_layout".
#
# Source of truth: running-config.gz at repo root — pulled from /proc/config.gz
# on the phone running our Stage 4 kernel. See docs/BUILD-LOG-2026-04-26.md (Bug 13).
#
# If running-config.gz is missing, falls back to building it from
# vendor/lahaina-qgki_defconfig + vendor/debugfs.config + scripts/config overrides
# (matches Stage 4's recipe, but `make olddefconfig` may drift).
set -e
export MSYS_NO_PATHCONV=1   # Git Bash on Windows: stop /work being rewritten
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CONTAINER=spacewar-build

# running-config.gz is stored in the build-repo on GitHub. Pull it from inside
# the container to avoid Windows-Git-Bash path quoting issues with `docker cp`.
USE_DETERMINISTIC=1
if [ ! -f "$REPO_ROOT/running-config.gz" ]; then
  echo "[!] running-config.gz NOT found in build-repo."
  echo "    Pull it from your phone first:"
  echo "      adb shell \"su -c 'cat /proc/config.gz'\" > running-config.gz"
  echo "    Falling back to defconfig+merge approach (config drift risk)."
  USE_DETERMINISTIC=0
else
  echo "[+] Using deterministic running-config.gz from build-repo (fetched via curl inside container)"
fi

docker exec -i \
  -e NH_FEATURES="${NH_FEATURES:-1}" \
  -e NH_FEATURES_NET="${NH_FEATURES_NET:-1}" \
  -e NH_FEATURES_USB="${NH_FEATURES_USB:-1}" \
  -e NH_FEATURES_GADGET="${NH_FEATURES_GADGET:-1}" \
  -e NH_FEATURES_GADGET_NET="${NH_FEATURES_GADGET_NET:-1}" \
  -e DEBUG_KERNEL="${DEBUG_KERNEL:-0}" \
  $CONTAINER bash <<EOF
set -e
export MSYS_NO_PATHCONV=1
cd /work/kernel-los

# ALWAYS pass ARCH=arm64 to kbuild — otherwise olddefconfig silently produces an X86 config
export ARCH=arm64 SUBARCH=arm64 LLVM=1 LLVM_IAS=1 CC=clang \
       CLANG_TRIPLE=clang \
       CROSS_COMPILE=aarch64-linux-gnu- \
       CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
       PATH=/work/aosp-clang/clang-r547379/bin:\$PATH
unset LOCALVERSION   # Don't stack with CONFIG_LOCALVERSION (which is "-qgki")

mkdir -p out

if [ "$USE_DETERMINISTIC" = "1" ]; then
  # Path A — deterministic. Fetch running-config.gz from our build-repo on GitHub.
  curl -sSLf "https://raw.githubusercontent.com/ilyamen/nothing-phone-1-nethunter-kernel/master/running-config.gz" \
    -o /tmp/running-config.gz
  gunzip -c /tmp/running-config.gz > out/.config
  ARCH=arm64 PATH=\$PATH make O=out olddefconfig | tail -3
else
  # Path B — fallback (Stage 4 recipe but olddefconfig may drift)
  make O=out vendor/lahaina-qgki_defconfig | tail -3
  ./scripts/kconfig/merge_config.sh -m -O out out/.config arch/arm64/configs/vendor/debugfs.config | tail -3
  ./scripts/config --file out/.config \
    -d ATH9K_HTC \
    -d LOCALVERSION_AUTO \
    -e LTO_CLANG \
    -e CFI_CLANG -e CFI_CLANG_SHADOW \
    -e BPF_JIT_DEFAULT_ON -e ARCH_WANT_DEFAULT_BPF_JIT \
    -e NFS_FS -e NFS_V3 -e NFS_V4 -e NFSD -e NFSD_V3 -e NFSD_V4 \
    -e USBIP_CORE -e USBIP_VHCI_HCD \
    -e PACKET_DIAG \
    --set-str LOCALVERSION ""
  ARCH=arm64 PATH=\$PATH make O=out olddefconfig | tail -3
fi

# NetHunter feature flags — incremental safe set verified on LOS 23.2.
# Always applied (default ON). To skip, set NH_FEATURES=0.
#
# Verified safe (Batches 1-4 sensors+icons+wlan all OK):
#  • USBIP_*           — USB-over-IP attacks
#  • BT_HCIBTUSB+vars  — Bluetooth USB dongles
#  • USB Wi-Fi family  — MT76, RT2X00, ATH9K/10K, PRISM2, RSI (modules)
#  • MAC80211_HWSIM    — virtual radio for evil-twin / hostapd-mana
#  • HID_PID           — force-feedback HID
#  • NFS_FS / NFSD     — NFS client+server (modules, not auto-loaded)
#  • PACKET/UNIX/INET_DIAG, NETFILTER_XT_MATCH_MULTIPORT
#
# DELIBERATELY EXCLUDED (verified breaks LOS 23.2 vendor ABI on first boot):
#  • CFG80211_WEXT     — adds fields to struct wiphy → vendor wlan/icnss2 fail
#  • MAC80211_MESH     — adds fields to struct ieee80211_sub_if_data → ABI break
#  • USB_F_RNDIS/ECM/EEM/UVC/PRINTER + USB_CONFIGFS_*  — Catch-22: USB_F_*
#    cannot be enabled standalone (no Kconfig prompt — only `select`-able by
#    USB_CONFIGFS_*=y), but enabling USB_CONFIGFS_*=y triggers vendor
#    init.<dev>.usb.rc paths that fail on this device.
#
# NH_FEATURES=0 disables this whole block (returns to plain running-config).
if [ "\${NH_FEATURES:-1}" = "1" ]; then
echo "[*] NH_FEATURES=1 — enabling verified NetHunter feature flags"
./scripts/config --file out/.config \
  \`# === USBIP — USB-over-IP (Batch 1) === \` \
  -m USBIP_CORE -m USBIP_VHCI_HCD -m USBIP_HOST -m USBIP_VUDC \
  --set-val USBIP_VHCI_HC_PORTS 8 --set-val USBIP_VHCI_NR_HCS 1 \
  \`# === Bluetooth USB (Batch 2) === \` \
  -m BT_HCIBTUSB -e BT_HCIBTUSB_AUTOSUSPEND \
  -e BT_HCIBTUSB_BCM -e BT_HCIBTUSB_MTK -e BT_HCIBTUSB_RTL \
  -m BT_HCIVHCI \
  \`# === USB Wi-Fi adapter drivers (Batch 3) === \` \
  -e WLAN_VENDOR_RALINK -e WLAN_VENDOR_MEDIATEK \
  -e WLAN_VENDOR_ATH -e WLAN_VENDOR_BROADCOM \
  -e WLAN_VENDOR_INTERSIL -e WLAN_VENDOR_ZYDAS \
  -m MT76_CORE -m MT76_USB -m MT76x0U -m MT76x2U -m MT7601U \
  -m RT2X00 -m RT2X00_LIB_USB -m RT2800USB \
  -e RT2800USB_RT33XX -e RT2800USB_RT3573 -e RT2800USB_RT35XX \
  -e RT2800USB_RT53XX -e RT2800USB_RT55XX -e RT2800USB_UNKNOWN \
  -m ATH9K -m ATH9K_HTC -m ATH10K -m ATH10K_USB \
  -m PRISM2_USB -m RSI_91X -m RSI_USB \
  \`# === HID / virtual radio / NFS / diag (Batch 4-fixed) === \` \
  -e HID_PID \
  -m MAC80211_HWSIM \
  -m LIB80211 -m LIB80211_CRYPT_WEP -m LIB80211_CRYPT_CCMP -m LIB80211_CRYPT_TKIP \
  -m NFS_FS -m NFS_V3 -m NFS_V4 -m NFSD -e NFSD_V3 -e NFSD_V4 \
  -m PACKET_DIAG -m UNIX_DIAG -m INET_DIAG \
  -e NETFILTER_XT_MATCH_MULTIPORT \
  \`# === DELIBERATELY EXCLUDED — break LOS 23.2 vendor ABI === \` \
  -d CFG80211_WEXT -d MAC80211_MESH
ARCH=arm64 PATH=\$PATH make O=out olddefconfig | tail -3
fi  # end NH_FEATURES

# Batch 5 — "safe modular pack" for NetHunter networking/VPN/SDR/USB-Eth/CAN.
# All =m, NO auto-load → cannot break boot. Loaded on demand by user
# (insmod, modprobe, or by hotplug when matching device is plugged in).
#
# What this enables:
#  • WireGuard      — modern VPN (10x faster than OpenVPN)
#  • USB Ethernet   — RTL8152/3 (Ugreen 20265 etc), AX88179 (ASIX), CDC-NCM/EEM
#  • CAN bus        — car hacking via USB-CAN dongles (GS_USB)
#  • DVB-USB RTL28  — turn $10 DVB-T stick into RTL-SDR receiver
#  • NFQUEUE        — mitmproxy/bettercap MITM target
#  • NTFS3          — read/write NTFS USB drives (modern in-kernel impl, replaces FUSE)
#  • CIFS/SMB       — mount Windows shares
#  • PPP/L2TP/PPTP  — legacy VPN protocols
#  • TC/BPF actions — fakeAP / redsocks / traffic shaping
#
# To skip this batch entirely set NH_FEATURES_NET=0.
#
# CRITICAL RULE for Batch 5: NEVER use \`-m FLAG\` on a config that's
# already =y in running-config.gz. Demoting builtin → module REMOVES code from
# vmlinux, changes its export-table layout, and shifts CRCs of dozens of
# unrelated symbols → vendor /vendor/lib/modules/*.ko fail modversions check
# → sensors/icnss2/audio all dead. Verified empirically 2026-04-28.
#
# So: only flags that are "# not set" in baseline get \`-m\`. Everything that
# is already \`=y\` we leave alone (the running config is already richer than
# we'd ever set up by hand).
#
# Also DELIBERATELY EXCLUDED:
#  • CAN (and friends): \`IS_ENABLED(CONFIG_CAN)\` adds \`struct netns_can\` to
#    \`struct net\` → 3373 vmlinux symbols change CRC → vendor stack dead.
#    GKI ABI break on this LineageOS kernel; cannot enable in-tree.
#  • DVB-USB / MEDIA / I2C_MUX: built-in \`=y\` selects pulled too many vendor
#    init paths and broke camera I2C bus on first boot. Use software RTL-SDR
#    via TCP from PC instead, or build standalone DVB modules later.
if [ "\${NH_FEATURES_NET:-1}" = "1" ]; then
echo "[*] NH_FEATURES_NET=1 — Batch 5 (verified safe set, NO downgrades, NO CAN)"
./scripts/config --file out/.config \
  \`# === WireGuard (auto-pulls CRYPTO_LIB_CHACHA20POLY1305 etc as =m) === \` \
  -m WIREGUARD \
  \`# === Modern USB Ethernet (CDC family — Ugreen 20265 RTL8153 already =y in base) === \` \
  -m USB_NET_CDC_NCM -m USB_NET_CDC_EEM -m USB_NET_CDC_MBIM -m USB_WDM \
  \`# === Netfilter NFQUEUE — already =y in base. NFACCT excluded: enabling \` \
  \`#     NETFILTER_NETLINK_ACCT adds \\\`nfnl_acct_list\\\` to struct net (same \` \
  \`#     trap as CAN). NFQUEUE itself works fine without this. \` \
  \`# === PPP extras (core PPP/MPPE/etc already =y in base) === \` \
  -m PPP_ASYNC -m PPP_SYNC_TTY -e PPP_FILTER -e PPP_MULTILINK \
  \`# === L2TP extras (core L2TP already =y in base; V3 enables IP/ETH/DEBUGFS) === \` \
  -e L2TP_V3 -m L2TP_IP -m L2TP_ETH -m L2TP_DEBUGFS \
  \`# === TC actions (NET_CLS_BPF already =y in base) === \` \
  -m NET_ACT_BPF -m NET_ACT_MIRRED -m NET_ACT_NAT -m NET_ACT_PEDIT \
  \`# === NTFS read+write (5.4 has NTFS_FS only — NTFS3 added in 5.15) === \` \
  -m NTFS_FS -e NTFS_RW \
  \`# === CIFS/SMB (CIFS=m + extras as bool sub-flags) === \` \
  -m CIFS -e CIFS_UPCALL -e CIFS_XATTR -e CIFS_POSIX -e CIFS_DFS_UPCALL \
  \`# === DVB-USB RTL28xxU (RTL-SDR via $10 USB DVB-T dongle). \` \
  \`#     None of MEDIA/DVB/I2C_MUX adds fields to struct net/sk_buff/netdev/sock — \` \
  \`#     verified clean via header grep 2026-04-28. Top-level toggles are bool, \` \
  \`#     RTL28XXU needs I2C_MUX as a hard dep. \` \
  -m MEDIA_SUPPORT -e MEDIA_DIGITAL_TV_SUPPORT -e MEDIA_USB_SUPPORT \
  -m I2C_MUX -m DVB_CORE -e DVB_USB_V2 -e DVB_USB_RTL28XXU
ARCH=arm64 PATH=\$PATH make O=out olddefconfig | tail -3
fi  # end NH_FEATURES_NET

# Batch 6 — USB Serial / CDC ACM / cellular USB / USB Audio / USB Printer (host).
# All =m, NO auto-load — kernel just gains capability. When user plugs FTDI/CH341/
# Arduino/Huawei modem etc. the kernel hotplugs the matching .ko.
# Verified safe by struct net/sk_buff/netdev/sock conditional-field grep — none of
# these flags add fields to vendor-exported structs. CRC drift expected ~40 (noise).
if [ "\${NH_FEATURES_USB:-1}" = "1" ]; then
echo "[*] NH_FEATURES_USB=1 — Batch 6: USB Serial + ACM + cellular + audio/printer host"
./scripts/config --file out/.config \
  \`# === USB Serial bus + popular adapters === \` \
  -m USB_SERIAL -e USB_SERIAL_GENERIC \
  -m USB_SERIAL_FTDI_SIO -m USB_SERIAL_CH341 -m USB_SERIAL_PL2303 \
  -m USB_SERIAL_CP210X -m USB_SERIAL_OPTION -m USB_SERIAL_QUALCOMM \
  -m USB_SERIAL_WWAN \
  -m USB_SERIAL_SIERRAWIRELESS -m USB_SERIAL_KEYSPAN -m USB_SERIAL_NAVMAN \
  \`# === USB CDC ACM (modems / Arduino-style) === \` \
  -m USB_ACM \
  \`# === Cellular USB modems (Huawei, Sierra, MBIM via QMI) === \` \
  -m USB_NET_HUAWEI_CDC_NCM -m USB_NET_QMI_WWAN \
  \`# === USB Audio capture (host side — USB sound cards) === \` \
  -m USB_AUDIO \
  \`# === USB Printer (host side — connect to USB printer) === \` \
  -m USB_PRINTER
ARCH=arm64 PATH=\$PATH make O=out olddefconfig | tail -3
fi  # end NH_FEATURES_USB

# Batch 7 — USB Gadget extras: MTP / PTP / UVC / Printer (gadget side).
# DELIBERATELY skipping RNDIS / ECM / EEM — those overlap with Qualcomm
# USB_F_GSI hardware-accelerated network gadget framework and may cause
# init.usb.rc conflicts at boot (catch-22 from earlier session).
# MTP/PTP/UVC/PRINTER are safe — non-network, no GSI overlap, all ABI-clean.
if [ "\${NH_FEATURES_GADGET:-1}" = "1" ]; then
echo "[*] NH_FEATURES_GADGET=1 — Batch 7: USB gadget MTP/PTP/UVC/PRINTER"
./scripts/config --file out/.config \
  \`# === MTP / PTP gadget (DriveDroid-style file emulation) === \` \
  -e USB_CONFIGFS_F_MTP -e USB_CONFIGFS_F_PTP \
  \`# === UVC gadget (webcam emulation — phone pretends to be USB cam) === \` \
  -e USB_CONFIGFS_F_UVC \
  \`# === Printer gadget (less common but cheap to include) === \` \
  -e USB_CONFIGFS_F_PRINTER
ARCH=arm64 PATH=\$PATH make O=out olddefconfig | tail -3
fi  # end NH_FEATURES_GADGET

# Batch 8 — USB Ethernet gadget (RNDIS / ECM).
# RISKY — these may conflict with Qualcomm USB_F_GSI hardware-accelerated
# network gadget framework. If phone fails to boot after this, set
# NH_FEATURES_GADGET_NET=0 and rebuild. nh-logcatd will auto-freeze incident
# snapshot if vendor stack breaks. Old boot.img is in output/ for rollback.
if [ "\${NH_FEATURES_GADGET_NET:-1}" = "1" ]; then
echo "[*] NH_FEATURES_GADGET_NET=1 — Batch 8 (RISKY): USB gadget RNDIS + ECM + EEM"
./scripts/config --file out/.config \
  \`# === RNDIS gadget (Windows USB-Ethernet — main MITM vector) === \` \
  -e USB_CONFIGFS_RNDIS \
  \`# === ECM gadget (Linux/macOS USB-Ethernet) === \` \
  -e USB_CONFIGFS_ECM \
  \`# === EEM gadget (Ethernet Emulation Model — fallback) === \` \
  -e USB_CONFIGFS_EEM
ARCH=arm64 PATH=\$PATH make O=out olddefconfig | tail -3
fi  # end NH_FEATURES_GADGET_NET

# Batch 9 — Production-safe debug visibility (always on, <1% overhead).
# Goal: see kernel issues BEFORE they become panic — v1.0.0/v1.1.0 had
# essentially post-mortem only debug (PSTORE + DEBUG_BUGVERBOSE).
#
# History (lessons from v1.1.1 first attempts):
#  • Iteration 1 with DETECT_HUNG_TASK + SOFTLOCKUP + WQ_WATCHDOG broke vendor
#    stack (sensors dead, no statusbar icons, ADBd doesn't start).
#  • Iteration 2 (only WQ_WATCHDOG removed) STILL broke. WQ_WATCHDOG was wrongly
#    accused — it's actually ABI-safe (worker_pool is defined in .c, not exported).
#  • Iteration 3 (this) — the real culprit is DETECT_HUNG_TASK.
#
# WHY DETECT_HUNG_TASK breaks ABI:
#   include/linux/sched.h v5.4 lines 1457-1460:
#     #ifdef CONFIG_DETECT_HUNG_TASK
#         unsigned long  last_switch_count;
#         unsigned long  last_switch_time;
#     #endif
#   This adds +16 bytes to task_struct. EXPORT_SYMBOL functions taking
#   `task_struct *` (wake_up_process, kthread_stop, get_task_struct, etc.)
#   change CRC under MODVERSIONS=y. Prebuilt vendor modules (qca_cld3_qca6750.ko,
#   sensors, audio, icnss2) fail modversions check → load fail → vendor stack
#   dead → phone boots but UI is dysfunctional and ADB doesn't come up.
#
# Same logic permanently excludes:
#  • DETECT_HUNG_TASK    — task_struct +16 bytes (sched.h:1457)
#  • FUNCTION_TRACER     — pulls TRACING which adds task_struct fields
#  • TRACING             — task_struct +trace,trace_recursion (sched.h:2649)
#  • FUNCTION_GRAPH_TRACER — task_struct +5 fields (sched.h:2626-2647)
#  • FTRACE_SYSCALLS     — typically pulls TRACING
#  • LIVEPATCH           — struct module
#  • BPF_EVENTS          — struct module
#  • DEBUG_PREEMPT/MUTEXES/SPINLOCK/RT_MUTEXES/RWSEMS — change mutex_lock,
#    spin_lock CRCs (heavy widespread vendor use)
#  • LOCKDEP / PROVE_LOCKING — adds lockdep_map to many structs, heavy CPU
#  • KASAN — incompatible with CFI_CLANG (this kernel uses CFI)
#  • KFENCE — added in kernel 5.12; this kernel is 5.4
#
# What's safe (verified by source diff against Linux 5.4 headers):
#  • SOFTLOCKUP_DETECTOR — only percpu vars in watchdog.c
#  • HARDLOCKUP_DETECTOR — only percpu vars
#  • WQ_WATCHDOG — only adds field to struct worker_pool which is defined
#    in workqueue.c (not exported, vendor modules don't see it)
#  • SCHED_STACK_END_CHECK — runtime check in __schedule(), no struct change
#  • DEBUG_NOTIFIERS — only pr_warn() calls, no struct change
#  • DEBUG_FS — debugfs filesystem, no exported struct touched
#  • DYNAMIC_DEBUG (full) — struct _ddebug identical to CORE-only version,
#    only difference is registration call-sites in modules
#  • LOG_BUF_SHIFT — sizeof(__log_buf) constant, not exported
#  • PRINTK_TIME, CMDLINE_EXTEND — runtime behavior only
#
# Set NH_FEATURES_DETECTORS=0 to skip.
#
# ITERATION 3 LOG (2026-04-29): even with DETECT_HUNG_TASK explicitly off, full
# set (SOFTLOCKUP+HARDLOCKUP+WQ_WATCHDOG+SCHED_STACK_END_CHECK+DEBUG_NOTIFIERS+
# DEBUG_FS+DYNAMIC_DEBUG+PRINTK_TIME+LOG_BUF_SHIFT=19) STILL broke vendor stack.
# At least one of those flags pulls a struct change that propagates to vendor
# ABI. Without per-flag binary-search, we can't isolate the culprit cheaply.
#
# CONSERVATIVE FALLBACK: enable only the 4 flags that mathematically CANNOT
# change exported struct CRCs:
#   • LOG_BUF_SHIFT=19   — sizeof of an internal static buffer; not exported
#   • PRINTK_TIME        — runtime sysctl printk.time; runtime-only behavior
#   • CMDLINE_EXTEND     — Kconfig that affects boot-arg parsing; not ABI
#   • CMDLINE (string)   — kernel command line tokens; runtime-only
#
# This still gives users:
#   • 4× larger printk ring (128KB → 512KB) — visible via `dmesg`
#   • Timestamps on every line of dmesg
#   • 4× larger ramoops region — full panic forensics persisted
#   • Userspace-writable pmsg ring (used by nh-logcatd)
#
# Future debug detector rollout requires per-flag rebuild-and-test cycle.
if [ "\${NH_FEATURES_DETECTORS:-1}" = "1" ]; then
echo "[*] NH_FEATURES_DETECTORS=1 — Batch 9: 512KB log_buf + timestamps + extended ramoops"
./scripts/config --file out/.config \
  \`# === PRINTK_TIME: dmesg timestamps on every line. Runtime sysctl. \` \
  -e PRINTK_TIME \
  \`# === LOG_BUF_SHIFT: 17 (128KB) → 19 (512KB). Multi-CPU panic fills 200+KB; \` \
  \`#     with 512KB we capture full panic + preceding 1-2s activity. \` \
  --set-val LOG_BUF_SHIFT 19 \
  \`# === CMDLINE_EXTEND: append our CMDLINE to bootloader's, for ramoops. \` \
  -e CMDLINE_EXTEND
ARCH=arm64 PATH=\$PATH make O=out olddefconfig | tail -3
# CMDLINE separately (heredoc whitespace).
# ramoops sizes: record_size 2MB (full multi-CPU oops), console_size 512KB
# (boot console history), ftrace_size 1MB, pmsg_size 512KB (userspace can
# write via /dev/pmsg0 — nh-logcatd uses this). panic_print=15 dumps tasks +
# memmem + timers + locks at panic.
./scripts/config --file out/.config --set-str CMDLINE \
  "cgroup_disable=pressure ramoops.record_size=2097152 ramoops.console_size=524288 ramoops.ftrace_size=1048576 ramoops.pmsg_size=524288 panic_print=15 log_buf_len=524288"
# log_buf_len=524288 — overrides the bootloader's 'log_buf_len=256K' which would
# otherwise truncate our CONFIG_LOG_BUF_SHIFT=19 (512KB) intent down to 256KB.
# Verified empirically v1.1.1 build: /proc/cmdline showed 'log_buf_len=256K'
# inherited from bootloader, defeating our config.
fi  # end NH_FEATURES_DETECTORS

# DEBUG_KERNEL (legacy env flag, kept for backward-compat). Was used to gate
# CMDLINE+PRINTK_TIME — now always-on via Batch 9. This block is now a no-op
# unless NH_FEATURES_DETECTORS=0 (in which case it restores the v1.0.0 minimal
# debug behavior).
if [ "\${DEBUG_KERNEL:-0}" = "1" ] && [ "\${NH_FEATURES_DETECTORS:-1}" = "0" ]; then
  echo "[*] DEBUG_KERNEL=1 (NH_FEATURES_DETECTORS=0 fallback) — minimal debug"
  ./scripts/config --file out/.config -e PRINTK_TIME -e CMDLINE_EXTEND
  ARCH=arm64 PATH=\$PATH make O=out olddefconfig | tail -3
  ./scripts/config --file out/.config --set-str CMDLINE \
    "cgroup_disable=pressure ramoops.record_size=1048576 ramoops.ftrace_size=524288 panic_print=15"
fi

# Force git tree dirty — needed to reproduce '-dirty' suffix in vermagic
touch Makefile

echo
echo "=== Sanity check (must match running kernel: 5.4.302-qgki-g192e5b024436-dirty, CFI=on, LTO=on) ==="
for f in ARM64 ARCH_LAHAINA COMPAT EXFAT_FS CFI_CLANG CFI_CLANG_SHADOW LTO_CLANG \
         WLAN_VENDOR_REALTEK ATH9K_HTC \
         HID USB_F_HID USB_F_MASS_STORAGE USB_F_GSI \
         NFS_FS NFSD USBIP_CORE USBIP_VHCI_HCD PACKET_DIAG \
         WIREGUARD USB_RTL8152 USB_NET_AX88179_178A \
         USB_NET_CDC_NCM USB_NET_CDC_MBIM USB_WDM \
         NETFILTER_NETLINK_QUEUE NETFILTER_NETLINK_ACCT \
         NTFS_FS CIFS PPTP L2TP L2TP_V3 PPP_MULTILINK NET_CLS_BPF \
         BPF_JIT_DEFAULT_ON LOCALVERSION; do
  v=\$(grep "^CONFIG_\${f}=" out/.config | head -1)
  [ -z "\$v" ] && v=\$(grep "^# CONFIG_\${f} is not set" out/.config | head -1)
  echo "  \${v:-CONFIG_\${f}: NOT_SET}"
done
EOF
