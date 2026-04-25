#!/bin/bash
# Setup Docker container for the kernel build.
# Run this on your host (Linux/Mac/Windows-with-Docker).
set -e

CONTAINER=spacewar-build
VOLUME=spacewar-vol

docker volume create $VOLUME 2>&1
docker rm -f $CONTAINER 2>/dev/null || true

docker run -d --name $CONTAINER \
  -v $VOLUME:/work -w /work \
  kalilinux/kali-rolling sleep infinity

docker exec $CONTAINER bash -c "
  apt-get update -qq && \
  apt-get install -y --no-install-recommends \
    build-essential bc bison flex libssl-dev libelf-dev libncurses-dev \
    python3 python-is-python3 git wget xz-utils zip unzip ccache rsync \
    ca-certificates curl clang lld llvm cpio kmod zstd \
    gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu \
    gcc-arm-linux-gnueabi binutils-arm-linux-gnueabi
"

# Neutron Clang's bundled ld.lld needs libxml2.so.2 (Kali has .so.16 only).
# Symlink — they're ABI compatible enough for our use.
docker exec $CONTAINER bash -c \
  "ln -sf /usr/lib/x86_64-linux-gnu/libxml2.so.16 /usr/lib/x86_64-linux-gnu/libxml2.so.2"

echo "[+] Container '$CONTAINER' ready."
echo "    Run scripts/02-clone-sources.sh next."
