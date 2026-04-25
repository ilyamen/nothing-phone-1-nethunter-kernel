#!/bin/bash
# Generate kernel .config:
# - lahaina-qgki_defconfig (spacewar baseline)
# - + EXFAT_FS=y (parity with official Kali)
# - Disable ATH9K_HTC (symbol conflict with QCACLD)
# - Disable CFI_CLANG (out-of-tree Realtek drivers crash on monitor mode otherwise)
# - Disable WLAN_VENDOR_REALTEK (use only out-of-tree modules for Realtek; in-tree drivers conflict)
# - Empty LOCALVERSION (avoid Kali codename leaking into kernel string)
set -e

CONTAINER=spacewar-build
HERE=$(dirname "$0")

docker cp "$HERE/configs/extras.config" $CONTAINER:/work/extras.config

docker exec $CONTAINER bash <<'EOF'
set -e
cd /work/kernel

# ALWAYS pass ARCH=arm64 to kbuild — otherwise olddefconfig silently produces an X86 config!
export ARCH=arm64 SUBARCH=arm64 LLVM=1 CC=clang CLANG_TRIPLE=aarch64-linux-gnu- \
       CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
       LOCALVERSION=-NetHunter \
       PATH=/work/aosp-clang/neutron/bin:$PATH

make distclean | tail -1
make O=out vendor/lahaina-qgki_defconfig | tail -1

# Apply our extras (just EXFAT for now)
ARCH=arm64 PATH=$PATH ./scripts/kconfig/merge_config.sh -O out -m out/.config /work/extras.config | tail -1

# Disable problem flags + clean LOCALVERSION
./scripts/config --file out/.config \
  -d ATH9K_HTC \
  -d ARCH_LAHAINA -d ARCH_SHIMA \
  -d CFI_CLANG -d CFI_CLANG_SHADOW \
  -d WLAN_VENDOR_REALTEK \
  --set-str LOCALVERSION ""

ARCH=arm64 PATH=$PATH make O=out olddefconfig | tail -1

echo
echo "=== Sanity check ==="
for f in ARM64 COMPAT EXFAT_FS CFI_CLANG WLAN_VENDOR_REALTEK ATH9K_HTC; do
  v=$(grep "^CONFIG_${f}=" out/.config | head -1)
  echo "  ${v:-CONFIG_${f}: NOT_SET}"
done
EOF
