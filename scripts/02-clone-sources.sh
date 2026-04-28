#!/bin/bash
# Clone all build inputs as specified in kernel-pin.env (in repo root).
# Verifies KERNEL_SHA matches HEAD after clone — protects against silent
# force-pushes to the kernel branch.
set -e
export MSYS_NO_PATHCONV=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PIN_FILE="$REPO_ROOT/kernel-pin.env"

if [ ! -f "$PIN_FILE" ]; then
  echo "[!] kernel-pin.env not found at $PIN_FILE"
  exit 1
fi

# Load pinning, export so docker exec sees them
set -a; . "$PIN_FILE"; set +a

CONTAINER=spacewar-build

docker exec -i \
  -e KERNEL_REPO -e KERNEL_REF -e KERNEL_SHA \
  -e ANYKERNEL_REPO -e ANYKERNEL_REF \
  -e RTL8188EUS_REPO -e RTL88X2BU_REPO -e RTL8821CU_REPO \
  -e TOOLCHAIN_VERSION -e TOOLCHAIN_URL -e MKDTBOIMG_URL \
  $CONTAINER bash -c '
set -e
export MSYS_NO_PATHCONV=1
cd /work

echo "[*] Cloning kernel from $KERNEL_REPO @ $KERNEL_REF"
rm -rf kernel-los
git clone --depth=50 -b "$KERNEL_REF" --single-branch "$KERNEL_REPO" kernel-los

# Verify SHA matches what kernel-pin.env says
ACTUAL_SHA=$(git -C kernel-los rev-parse HEAD)
if [ "$ACTUAL_SHA" != "$KERNEL_SHA" ]; then
  echo "[!] KERNEL_SHA mismatch!"
  echo "    expected: $KERNEL_SHA"
  echo "    got:      $ACTUAL_SHA"
  echo "    Either kernel was force-pushed or pin file is stale."
  exit 1
fi
echo "[+] kernel SHA verified: $ACTUAL_SHA"

# Out-of-tree Realtek drivers
[ -d rtl8188eus ]      || git clone --depth=1 "$RTL8188EUS_REPO"
[ -d 88x2bu-20210702 ] || git clone --depth=1 "$RTL88X2BU_REPO"
[ -d 8821cu-20210916 ] || git clone --depth=1 "$RTL8821CU_REPO"

# AnyKernel3 — kimocoder spacewar branch
[ -d ak3-spacewar ]    || git clone --depth=1 -b "$ANYKERNEL_REF" "$ANYKERNEL_REPO" ak3-spacewar

# mkdtboimg.py — needed by 07-package-zip.sh
curl -sLf "$MKDTBOIMG_URL" -o /work/kernel-los/scripts/mkdtboimg.py
chmod +x /work/kernel-los/scripts/mkdtboimg.py

# AOSP Clang
mkdir -p aosp-clang
cd aosp-clang
if [ ! -d "clang-$TOOLCHAIN_VERSION" ]; then
  echo "[*] Downloading AOSP Clang $TOOLCHAIN_VERSION (~6 GB)…"
  wget -q --show-progress "$TOOLCHAIN_URL" -O "clang-$TOOLCHAIN_VERSION.tar.gz"
  mkdir -p "clang-$TOOLCHAIN_VERSION"
  tar -xf "clang-$TOOLCHAIN_VERSION.tar.gz" -C "clang-$TOOLCHAIN_VERSION"
  rm -f "clang-$TOOLCHAIN_VERSION.tar.gz"
fi
"clang-$TOOLCHAIN_VERSION/bin/clang" --version | head -1
'

echo "[+] All sources cloned + SHA verified. Run scripts/03-apply-patches.sh next."
