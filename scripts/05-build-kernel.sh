#!/bin/bash
# Build the kernel Image using AOSP Clang r547379 (matches kimocoder/build.sh exactly).
set -e
export MSYS_NO_PATHCONV=1   # Git Bash on Windows: stop /work being rewritten to C:/Program Files/Git/work

CONTAINER=spacewar-build

docker exec -i $CONTAINER bash <<'EOF'
set -e
export MSYS_NO_PATHCONV=1   # Git Bash on Windows: stop /work being rewritten to C:/Program Files/Git/work
cd /work/kernel-los

export PATH=/work/aosp-clang/clang-r547379/bin:$PATH
export ARCH=arm64 SUBARCH=arm64 LLVM=1 LLVM_IAS=1 CC=clang
export CLANG_TRIPLE=clang
export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_ARM32=arm-linux-gnueabi-
unset LOCALVERSION   # CONFIG_LOCALVERSION="-qgki" is set in running config; LOCALVERSION env stacks → "-qgki-NetHunter" mismatch

# Force git tree dirty — required to reproduce running kernel's "-dirty" vermagic suffix
touch Makefile

J=$(nproc)
echo "[*] Building with AOSP Clang r547379 on $J threads…"
clang --version | head -1
time make O=out -j$J Image dtbs modules
echo
echo "[*] Installing modules to out/modules_install/ (no DEPMOD strip)…"
INSTALL_MOD_PATH=/work/kernel/out/modules_install \
INSTALL_MOD_STRIP=1 \
make O=out -j$J modules_install
echo
echo "[*] Generating modules.builtin metadata…"
make O=out -j$J modules.builtin
echo
echo "[+] Image: $(ls -lh out/arch/arm64/boot/Image)"
echo "[+] Kernel version: $(cat out/include/config/kernel.release)"
echo "[+] Module count built: $(find out/modules_install -name '*.ko' 2>/dev/null | wc -l)"
echo "[+] Wireless drivers built-in: $(grep -c wireless out/modules.builtin)"
EOF
