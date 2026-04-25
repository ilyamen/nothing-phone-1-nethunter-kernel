#!/bin/bash
# Package kernel + modules into AnyKernel3 zip flashable via Franco Kernel Manager.
# Uses the official Kali NetHunter spacewar AnyKernel3 layout as base.
set -e

CONTAINER=spacewar-build

docker exec $CONTAINER bash <<'EOF'
set -e

AK=/work/ak3-spacewar
mkdir -p $AK

# Get the official Kali NetHunter spacewar A14 zip (we only need the kernel-nethunter.zip
# inside it for the AnyKernel3 layout, then we replace the Image and modules).
if [ ! -f /work/official-spacewar.zip ]; then
  echo "[*] Downloading official Kali NetHunter spacewar A14 (~2.5 GB)..."
  wget -q --show-progress \
    https://kali.download/nethunter-images/current/kali-nethunter-2026.1-spacewar-fourteen-full.zip \
    -O /work/official-spacewar.zip 2>&1 | tail -2
fi

mkdir -p /work/official-ext
cd /work/official-ext
[ -f kernel-nethunter.zip ] || unzip -q /work/official-spacewar.zip kernel-nethunter.zip
cd $AK
[ -f anykernel.sh ] || unzip -q /work/official-ext/kernel-nethunter.zip
ls $AK | head

# Replace Image with our build
cp /work/kernel/out/arch/arm64/boot/Image $AK/Image

# Replace modules + metadata
NEW_DIR=$AK/modules/vendor/lib/modules/5.4.281-NetHunter
mkdir -p $NEW_DIR/kernel/drivers/net/wireless/realtek
# Rename existing module dir if it has different version
for d in $AK/modules/vendor/lib/modules/*/; do
  ver=$(basename $d)
  if [ "$ver" != "5.4.281-NetHunter" ]; then
    mv $d $NEW_DIR
  fi
done

cp /work/modules/8188eu.ko  $NEW_DIR/kernel/drivers/net/wireless/realtek/
cp /work/modules/88x2bu.ko  $NEW_DIR/kernel/drivers/net/wireless/realtek/
cp /work/modules/8821cu.ko  $NEW_DIR/kernel/drivers/net/wireless/realtek/

cp /work/kernel/out/modules.builtin          $NEW_DIR/modules.builtin
cp /work/kernel/out/modules.builtin.modinfo  $NEW_DIR/modules.builtin.modinfo

depmod -b $AK/modules/vendor 5.4.281-NetHunter

# Don't include dtb/dtbo — let AnyKernel3 keep the existing ones on the device
rm -f $AK/dtb $AK/dtbo.img

# Pack
cd $AK
ZIP=/work/spacewar-nethunter-FINAL.zip
rm -f $ZIP
zip -qr9 $ZIP . -x "*.git*"
ls -lh $ZIP
EOF

# Pull the zip out
mkdir -p output
docker cp $CONTAINER:/work/spacewar-nethunter-FINAL.zip output/
ls -lh output/
