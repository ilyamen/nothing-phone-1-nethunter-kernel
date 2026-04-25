#!/bin/bash
# Clone the kernel source, AnyKernel3, and the 3 Realtek out-of-tree drivers.
# Plus download Neutron Clang.
set -e

CONTAINER=spacewar-build

docker exec $CONTAINER bash -c '
cd /work

# Kernel source — kimocoder branch XOS-14.0.2
git clone --depth=1 -b XOS-14.0.2 https://github.com/kimocoder/kernel_nothing_sm7325 kernel

# Out-of-tree Realtek drivers
git clone --depth=1 https://github.com/aircrack-ng/rtl8188eus
git clone --depth=1 https://github.com/morrownr/88x2bu-20210702
git clone --depth=1 https://github.com/morrownr/8821cu-20210916

# Kali NetHunter kernel-builder (provides patches/, anykernel.sh templates, etc.)
git clone --depth=1 https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-kernel-builder kernel/kali-nethunter-kernel

# AnyKernel3 (we use the official Kali NetHunter spacewar AnyKernel3 layout)
mkdir -p ak3-spacewar

# Download Neutron Clang 19 — kernel-tuned LLVM
mkdir -p aosp-clang
cd aosp-clang
wget -q --show-progress https://github.com/Neutron-Toolchains/clang-build-catalogue/releases/download/10032024/neutron-clang-10032024.tar.zst -O neutron.tar.zst
mkdir -p neutron && cd neutron && tar -I zstd -xf ../neutron.tar.zst
bin/clang --version | head -1
'

echo "[+] Sources cloned. Run scripts/03-apply-patches.sh next."
