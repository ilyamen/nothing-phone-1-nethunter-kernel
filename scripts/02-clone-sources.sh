#!/bin/bash
# Clone the kernel source, AnyKernel3, and the 3 Realtek out-of-tree drivers.
# Plus download AOSP Clang r536225 (the toolchain kimocoder uses in his official build.sh).
#
# Source: kimocoder/android_kernel_lineage_nothing_sm7325 branch nethunter-23.0
#   - Linux 5.4.300 (newest LTS for this device)
#   - kernel base: android13-5.4-lahaina (compatible with AOSPA Topaz / LineageOS 20+)
#   - device-specific spacewar_defconfig with NetHunter prerequisites already enabled
#   - active LineageOS upstream + ASB security bulletin merges
#   - has explicit "qcacld: enable direct monitor mode through 'iw'" patch
set -e
export MSYS_NO_PATHCONV=1   # Git Bash on Windows: stop /work being rewritten to C:/Program Files/Git/work

CONTAINER=spacewar-build

docker exec -i $CONTAINER bash -c '
set -e
export MSYS_NO_PATHCONV=1   # Git Bash on Windows: stop /work being rewritten to C:/Program Files/Git/work
cd /work

# Kernel source — kimocoder lineage repo, nethunter-23.0 branch
git clone --depth=1 -b nethunter-23.0 \
  https://github.com/kimocoder/android_kernel_lineage_nothing_sm7325 kernel

# Out-of-tree Realtek drivers
git clone --depth=1 https://github.com/aircrack-ng/rtl8188eus
git clone --depth=1 https://github.com/morrownr/88x2bu-20210702
git clone --depth=1 https://github.com/morrownr/8821cu-20210916

# AnyKernel3 — kimocoder spacewar branch (purpose-built; supports Android 11-16)
git clone --depth=1 -b spacewar https://github.com/kimocoder/AnyKernel3 ak3-spacewar

# Kali NetHunter kernel-builder — for the QCACLD-3.0 packet injection patch series.
# 17 patches that add wlan_hdd_frame_inject.* + flip CONFIG_FEATURE_FRAME_INJECTION_SUPPORT=y.
# Applied at build time by 03-apply-patches.sh.
git clone --depth=1 \
  https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-kernel-builder \
  kali-kernel-builder

# mkdtboimg.py — needed for 07-package-zip.sh to assemble dtbo.img from per-board overlays.
# Lineage repo does not ship it; pull from kimocoder/kernel_nothing_sm7325 (Apache 2.0, AOSP origin).
curl -sLf "https://raw.githubusercontent.com/kimocoder/kernel_nothing_sm7325/nethunter-15.0/scripts/mkdtboimg.py" \
  -o /work/kernel/scripts/mkdtboimg.py
chmod +x /work/kernel/scripts/mkdtboimg.py

# AOSP Clang r536225 (Clang 18.0.4) — the toolchain in kimocoder/build.sh.
# Mirror via SA9990/Toolchain to avoid AOSP googlesource throttling.
mkdir -p aosp-clang
cd aosp-clang
if [ ! -d clang-r536225 ]; then
  wget -q --show-progress \
    https://github.com/SA9990/Toolchain/releases/download/clang-r536225/clang-r536225.tar.gz \
    -O clang-r536225.tar.gz || \
  wget -q --show-progress \
    https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main-kernel/clang-r536225.tar.gz \
    -O clang-r536225.tar.gz
  mkdir -p clang-r536225
  tar -xf clang-r536225.tar.gz -C clang-r536225
fi
clang-r536225/bin/clang --version | head -1
'

echo "[+] Sources cloned. Run scripts/03-apply-patches.sh next."
