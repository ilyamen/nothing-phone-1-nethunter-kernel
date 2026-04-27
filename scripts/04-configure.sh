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

# Push running-config.gz into container if present
if [ -f "$REPO_ROOT/running-config.gz" ]; then
  docker cp "$REPO_ROOT/running-config.gz" $CONTAINER:/tmp/running-config.gz
  echo "[+] Using deterministic running-config.gz from repo (matches phone slot_a Stage 4)"
  USE_DETERMINISTIC=1
else
  echo "[!] running-config.gz NOT found in repo root."
  echo "    Pull it from your phone first:"
  echo "      adb shell \"su -c 'cat /proc/config.gz'\" > running-config.gz"
  echo "    Falling back to defconfig+merge approach (config drift risk)."
  USE_DETERMINISTIC=0
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
  # Path A — deterministic
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

# Force git tree dirty — needed to reproduce '-dirty' suffix in vermagic
# (running kernel is '5.4.302-qgki-g192e5b024436-dirty')
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
