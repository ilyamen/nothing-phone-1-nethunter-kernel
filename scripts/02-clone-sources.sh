#!/bin/bash
# Clone the kernel source, AnyKernel3, and the 3 Realtek out-of-tree drivers.
# Plus download AOSP Clang r547379 (the toolchain kimocoder uses in his official build.sh).
#
# Source: ilyamen/android_kernel_nothing_sm7325_nethunter branch nethunter-23.2
#   - Fork of LineageOS/android_kernel_nothing_sm7325 lineage-23.2
#   - + Kali NetHunter QCACLD-3.0 frame injection commits (8 selected from the
#     17-patch series — patches 01, 02, 05, 06, 07, 13, 14, 15)
#   - Linux 5.4.302 (newest LTS for this device)
#   - device-specific spacewar_defconfig with NetHunter prerequisites
set -e
export MSYS_NO_PATHCONV=1   # Git Bash on Windows: stop /work being rewritten to C:/Program Files/Git/work

CONTAINER=spacewar-build

docker exec -i $CONTAINER bash -c '
set -e
export MSYS_NO_PATHCONV=1
cd /work

# Kernel source — our fork with NetHunter QCACLD inject already integrated
git clone --depth=50 -b nethunter-23.2 --single-branch \
  https://github.com/ilyamen/android_kernel_nothing_sm7325_nethunter kernel-los

# Out-of-tree Realtek drivers
git clone --depth=1 https://github.com/aircrack-ng/rtl8188eus
git clone --depth=1 https://github.com/morrownr/88x2bu-20210702
git clone --depth=1 https://github.com/morrownr/8821cu-20210916

# AnyKernel3 — kimocoder spacewar branch (purpose-built; supports Android 11-16)
git clone --depth=1 -b spacewar https://github.com/kimocoder/AnyKernel3 ak3-spacewar

# mkdtboimg.py — needed for 07-package-zip.sh to assemble dtbo.img from per-board overlays.
# Lineage repo does not ship it; pull from kimocoder/kernel_nothing_sm7325 (Apache 2.0, AOSP origin).
curl -sLf "https://raw.githubusercontent.com/kimocoder/kernel_nothing_sm7325/nethunter-15.0/scripts/mkdtboimg.py" \
  -o /work/kernel-los/scripts/mkdtboimg.py
chmod +x /work/kernel-los/scripts/mkdtboimg.py

# AOSP Clang r547379 (Clang 19.0.1) — current LineageOS-grade kernel toolchain
# from android.googlesource.com prebuilts/clang/host/linux-x86 main-kernel branch.
mkdir -p aosp-clang
cd aosp-clang
if [ ! -d clang-r547379 ]; then
  wget -q --show-progress \
    "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main-kernel/clang-r547379.tar.gz" \
    -O clang-r547379.tar.gz
  mkdir -p clang-r547379
  tar -xf clang-r547379.tar.gz -C clang-r547379
  rm -f clang-r547379.tar.gz
fi
clang-r547379/bin/clang --version | head -1
'

echo "[+] Sources cloned. Run scripts/03-apply-patches.sh next."
