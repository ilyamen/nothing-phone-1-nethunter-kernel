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

docker exec -i $CONTAINER bash <<EOF
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

# DEBUG-KERNEL knobs (set DEBUG_KERNEL=1 env to enable). MINIMAL set —
# only what's needed to make ramoops save panic stacktraces.
# Lessons from a previous attempt: KALLSYMS_ALL + DEBUG_KERNEL + DEBUG_BUGVERBOSE
# caused LineageOS 23.2 vendor modules (sensors, audio, network indicators)
# to fail to load. Keep config minimal. ramoops.record_size override comes
# via kernel CMDLINE since this device's DT does not declare it.
if [ "\${DEBUG_KERNEL:-0}" = "1" ]; then
  echo "[*] DEBUG_KERNEL=1 — enabling minimal debug knobs"
  ./scripts/config --file out/.config \
    -e PRINTK_TIME \
    -e CMDLINE_EXTEND
  ARCH=arm64 PATH=\$PATH make O=out olddefconfig | tail -3
  # Set CMDLINE separately to avoid heredoc whitespace issues
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
         BPF_JIT_DEFAULT_ON LOCALVERSION; do
  v=\$(grep "^CONFIG_\${f}=" out/.config | head -1)
  [ -z "\$v" ] && v=\$(grep "^# CONFIG_\${f} is not set" out/.config | head -1)
  echo "  \${v:-CONFIG_\${f}: NOT_SET}"
done
EOF
