#!/bin/bash
# Build the kernel Image using Neutron Clang.
set -e

CONTAINER=spacewar-build

docker exec $CONTAINER bash <<'EOF'
set -e
cd /work/kernel

export PATH=/work/aosp-clang/neutron/bin:$PATH
export ARCH=arm64 SUBARCH=arm64 LLVM=1 CC=clang
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_ARM32=arm-linux-gnueabi-
export LOCALVERSION=-NetHunter

J=$(nproc)
echo "[*] Building with Neutron Clang on $J threads…"
clang --version | head -1
time make O=out -j$J Image
echo
echo "[*] Generating modules.builtin metadata…"
make O=out -j$J modules.builtin
echo
echo "[+] Image: $(ls -lh out/arch/arm64/boot/Image)"
echo "[+] Kernel version: $(cat out/include/config/kernel.release)"
echo "[+] Wireless drivers built-in: $(grep -c wireless out/modules.builtin)"
EOF
