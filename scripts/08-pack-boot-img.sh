#!/bin/bash
# Repack stock boot.img with our freshly built kernel Image using magiskboot.
# Output: output/nethunter-23.2-${TAG}-boot_a.img (TAG defaults to "latest")
#
# Inputs (must exist before running):
#   • Stock boot_a.img backup at local-backup-20260427-1822/boot_a.img
#     (this is the original LineageOS boot.img we pulled from the phone)
#   • Freshly built kernel Image at /work/kernel-los/out/arch/arm64/boot/Image
#     (produced by 05-build-kernel.sh)
#   • magiskboot tool at /work/ak3-spacewar/tools/magiskboot
#
# magiskboot must run inside the container — it's a Linux ELF.
set -e
export MSYS_NO_PATHCONV=1
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CONTAINER=spacewar-build
TAG="${1:-latest}"
STOCK_BOOT="$REPO_ROOT/local-backup-20260427-1822/boot_a.img"
OUT="$REPO_ROOT/output/nethunter-23.2-${TAG}-boot_a.img"

if [ ! -f "$STOCK_BOOT" ]; then
  echo "[!] Stock boot.img not found at: $STOCK_BOOT"
  echo "    Pull it from phone first via fastboot / TWRP backup."
  exit 1
fi

mkdir -p "$REPO_ROOT/output"

# Stream stock boot.img into container via stdin (avoids docker-cp Windows path bugs).
cat "$STOCK_BOOT" | docker exec -i $CONTAINER bash -c 'cat > /work/stock-boot.img'

docker exec -i $CONTAINER bash <<'EOF'
set -e
export MSYS_NO_PATHCONV=1
WORK=/tmp/repack-boot
rm -rf $WORK && mkdir -p $WORK && cd $WORK

cp /work/stock-boot.img boot.img
/work/ak3-spacewar/tools/magiskboot unpack boot.img >/dev/null

# Replace kernel — magiskboot creates kernel + ramdisk.cpio etc.
cp /work/kernel-los/out/arch/arm64/boot/Image kernel

/work/ak3-spacewar/tools/magiskboot repack boot.img new-boot.img >/dev/null
ls -lh new-boot.img
cp new-boot.img /work/repacked-boot.img
EOF

# Stream result out via stdout (avoids docker-cp Windows path bugs).
docker exec $CONTAINER cat /work/repacked-boot.img > "$OUT"
echo "[+] Built: $(ls -lh "$OUT")"
echo
echo "Flash with:"
echo "  adb -s b2f746b1 reboot bootloader"
echo "  fastboot -s b2f746b1 flash boot_a $(realpath --relative-to="$REPO_ROOT" "$OUT")"
echo "  fastboot -s b2f746b1 reboot"
