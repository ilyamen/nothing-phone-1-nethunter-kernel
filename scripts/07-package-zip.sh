#!/bin/bash
# Package kernel + dtb + dtbo + modules into AnyKernel3 zip flashable via Franco Kernel Manager.
# Uses kimocoder/AnyKernel3 spacewar branch (purpose-built, supports Android 11-16).
set -e
export MSYS_NO_PATHCONV=1   # Git Bash on Windows: stop /work being rewritten to C:/Program Files/Git/work

CONTAINER=spacewar-build

docker exec -i $CONTAINER bash <<'EOF'
set -e
export MSYS_NO_PATHCONV=1   # Git Bash on Windows: stop /work being rewritten to C:/Program Files/Git/work

AK=/work/ak3-spacewar
DTS_DIR=/work/kernel/out/arch/arm64/boot/dts/vendor/qcom

# Sanity check
if [ ! -d "$AK" ] || [ ! -f "$AK/anykernel.sh" ]; then
  echo "[!] AnyKernel3 missing at $AK — run 02-clone-sources.sh"
  exit 1
fi

# Pull latest in case there were upstream tweaks
cd $AK && git fetch --depth=1 origin spacewar 2>/dev/null && git reset --hard origin/spacewar 2>/dev/null || true

# Clean old artefacts
rm -f  $AK/Image $AK/dtb $AK/dtbo.img
rm -rf $AK/modules/vendor/lib/modules/*

# Image
cp /work/kernel/out/arch/arm64/boot/Image $AK/Image

# Concatenate all DTBs into one + build dtbo from .dtbo overlays (kimocoder pattern)
cat $DTS_DIR/*.dtb > $AK/dtb
python3 /work/kernel/scripts/mkdtboimg.py create $AK/dtbo.img --page_size=4096 $DTS_DIR/*.dtbo

# Modules — LineageOS-spacewar style FLAT layout: /vendor/lib/modules/*.ko
# (LOS' init.target.rc invokes `modprobe -a -d /vendor/lib/modules <names...>` directly,
#  not via /vendor/lib/modules/<KVER>/.) All in-kernel-tree .ko's go here so vermagic
#  matches the running kernel exactly and modprobe loads everything.
KVER=$(cat /work/kernel/out/include/config/kernel.release)
FLAT=$AK/modules/vendor/lib/modules
mkdir -p $FLAT

# Copy ALL freshly-built kernel modules (flat — strip directory hierarchy)
find /work/kernel/out/modules_install/lib/modules -name '*.ko' -exec cp {} $FLAT/ \; 2>/dev/null || true
echo "[+] Copied $(ls $FLAT/*.ko 2>/dev/null | wc -l) kernel modules into flat /vendor/lib/modules/"

# Plus our 3 out-of-tree Realtek drivers (also flat)
cp /work/modules/8188eu.ko  $FLAT/
cp /work/modules/88x2bu.ko  $FLAT/
cp /work/modules/8821cu.ko  $FLAT/

# Module metadata — depmod over the flat dir
( cd $FLAT && \
  cp /work/kernel/out/modules_install/lib/modules/$KVER/modules.dep . 2>/dev/null || true; \
  cp /work/kernel/out/modules.builtin .; \
  cp /work/kernel/out/modules.builtin.modinfo .; \
  cp /work/kernel/out/modules_install/lib/modules/$KVER/modules.alias . 2>/dev/null || true; \
  cp /work/kernel/out/modules_install/lib/modules/$KVER/modules.softdep . 2>/dev/null || true; \
)

# Re-run depmod against flat layout to regenerate modules.dep with correct relative paths
depmod -b $AK/modules/vendor -F /work/kernel/out/System.map -e $KVER 2>/dev/null || \
depmod -b $AK/modules/vendor $KVER 2>/dev/null || true

# Move depmod-generated metadata up out of <KVER>/ subdir into flat layout if needed
if [ -d $AK/modules/vendor/lib/modules/$KVER ]; then
  mv $AK/modules/vendor/lib/modules/$KVER/modules.* $FLAT/ 2>/dev/null || true
  rmdir $AK/modules/vendor/lib/modules/$KVER 2>/dev/null || true
fi

echo "[+] Modules + metadata in $FLAT:"
ls $FLAT | head -20
echo "..."
echo "[+] Total .ko files: $(ls $FLAT/*.ko 2>/dev/null | wc -l)"

# Pack
cd $AK
ZIP=/work/spacewar-nethunter-FINAL.zip
rm -f $ZIP
zip -qr9 $ZIP . -x "*.git*" "*README.md*" "*placeholder*"
echo "[+] Built: $(ls -lh $ZIP)"
echo "[+] Kernel version inside: $KVER"
EOF

# Pull the zip out
mkdir -p output
docker cp $CONTAINER:/work/spacewar-nethunter-FINAL.zip output/
ls -lh output/
