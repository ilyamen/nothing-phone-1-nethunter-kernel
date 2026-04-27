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

# NetHunter feature flags — full kali-nethunter-15.0 set adapted for our 23.2 base.
# OPT-IN via NH_FEATURES=1. Default OFF because the previous attempt to enable
# the full set in one go broke LineageOS 23.2 vendor modules (sensors/icons
# disappeared on first boot) — the USB_CONFIGFS_* / USB_F_RNDIS=y changes are
# suspected. Add features in small batches and test after each.
if [ "\${NH_FEATURES:-0}" = "1" ]; then
echo "[*] NH_FEATURES=1 — enabling full NetHunter feature flags (RISKY)"
./scripts/config --file out/.config \
  \`# === USBIP — USB-over-IP (USBIP attacks) === \` \
  -m USBIP_CORE -m USBIP_VHCI_HCD -m USBIP_HOST -m USBIP_VUDC \
  --set-val USBIP_VHCI_HC_PORTS 8 --set-val USBIP_VHCI_NR_HCS 1 \
  \`# === USB gadget functions (BadUSB / fake-anything) === \` \
  -m USB_F_RNDIS -m USB_F_ECM -m USB_F_EEM -m USB_F_OBEX \
  -m USB_F_PRINTER -m USB_F_SUBSET -m USB_F_SS_LB \
  -m USB_F_UAC1 -m USB_F_UAC2 -m USB_F_UVC \
  -e USB_CONFIGFS_RNDIS -e USB_CONFIGFS_ECM -e USB_CONFIGFS_ECM_SUBSET \
  -e USB_CONFIGFS_EEM -e USB_CONFIGFS_OBEX -e USB_CONFIGFS_F_PRINTER \
  -e USB_CONFIGFS_F_LB_SS -e USB_CONFIGFS_F_UAC1 -e USB_CONFIGFS_F_UAC1_LEGACY \
  -e USB_CONFIGFS_F_UVC \
  \`# === HID / force feedback === \` \
  -e HID_PID \
  \`# === 802.11 stack — virtual radio, mesh, wireless extensions === \` \
  -m MAC80211_HWSIM -e MAC80211_LEDS -e MAC80211_MESH \
  -e CFG80211_WEXT -e CFG80211_CRDA_SUPPORT \
  -m LIB80211 -m LIB80211_CRYPT_WEP -m LIB80211_CRYPT_CCMP -m LIB80211_CRYPT_TKIP \
  \`# === USB Wi-Fi adapters (random USB dongles) === \` \
  -m MT76_USB -m MT76x0U -m MT76x2U -m MT7601U \
  -m RT2X00 -m RT2X00_LIB_USB -m RT2800USB \
  -e RT2800USB_RT33XX -e RT2800USB_RT3573 -e RT2800USB_RT35XX \
  -e RT2800USB_RT53XX -e RT2800USB_RT55XX -e RT2800USB_UNKNOWN \
  -m RTL8187 -e RTL8187_LEDS -m RTL8192CU -m RTL8XXXU -e RTL8XXXU_UNTESTED \
  -m RTLWIFI_USB -m ATH9K -m ATH9K_HTC -m ATH10K_USB \
  -m PRISM2_USB -m RSI_USB -m LIBERTAS_USB -m BRCMFMAC \
  \`# === Bluetooth USB === \` \
  -m BT_HCIBTUSB -e BT_HCIBTUSB_AUTOSUSPEND \
  -e BT_HCIBTUSB_BCM -e BT_HCIBTUSB_MTK -e BT_HCIBTUSB_RTL \
  -e BT_BCM -e BT_RTL -e BT_MTKSDIO \
  -m BT_HCIVHCI -m BT_HCIBPA10X -m BT_HCIBFUSB -m BT_HCIBCM203X \
  \`# === NFS server/client (for sharing during pentest) === \` \
  -m NFS_FS -m NFS_V3 -m NFS_V4 -m NFSD -e NFSD_V3 -e NFSD_V4 \
  \`# === Misc useful for tools === \` \
  -m PACKET_DIAG -m UNIX_DIAG -m INET_DIAG \
  -e NETFILTER_XT_MATCH_MULTIPORT
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
