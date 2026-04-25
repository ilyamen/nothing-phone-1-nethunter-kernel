#!/bin/bash
# Build the 3 Realtek out-of-tree drivers as .ko modules against the freshly built kernel.
set -e

CONTAINER=spacewar-build

docker exec $CONTAINER bash <<'EOF'
set -e
ENV="ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC=clang LLVM=1 \
     CLANG_TRIPLE=aarch64-linux-gnu- \
     KSRC=/work/kernel/out KBUILD_OUTPUT=/work/kernel/out \
     CONFIG_PLATFORM_I386_PC=n CONFIG_PLATFORM_ANDROID_ARM64=y"

J=$(nproc)
mkdir -p /work/modules

for d in /work/rtl8188eus /work/88x2bu-20210702 /work/8821cu-20210916; do
  echo "[*] Building $(basename $d)…"
  cd $d
  make clean >/dev/null 2>&1 || true
  rm -f *.ko
  PATH=/work/aosp-clang/neutron/bin:$PATH eval make $ENV \
       KCFLAGS=-fno-stack-protector -j$J >/dev/null 2>&1
  KO=$(ls *.ko 2>/dev/null)
  if [ -z "$KO" ]; then
    echo "[!] $(basename $d): build failed"
    exit 1
  fi
  cp $KO /work/modules/
  llvm-strip --strip-debug /work/modules/$KO
  echo "[+] $(basename $d): $KO ($(ls -lh /work/modules/$KO | awk '{print $5}') stripped)"
done

echo
echo "[+] All modules in /work/modules/:"
ls -lh /work/modules/
echo
echo "[+] Vermagic check (must match kernel):"
for f in /work/modules/*.ko; do
  printf "  %-15s " "$(basename $f):"
  strings $f | grep vermagic | head -1
done
EOF
