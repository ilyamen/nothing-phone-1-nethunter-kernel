# Build instructions

The whole build runs inside a Docker container based on `kalilinux/kali-rolling`. You need only Docker on your host.

## Why Docker?

- Reproducible: same Kali base, same packages.
- Doesn't pollute host (kernel build pulls a couple GB of toolchains).
- Crucially: **the kernel source contains both `xt_DSCP.c` and `xt_dscp.c`** (different files). NTFS is case-INSENSITIVE on Windows. Bind-mounting the source from a Windows host loses one of them and the build fails on `xt_DSCP.o` missing. Use a Docker named volume instead — it lives on the Linux side.

## Quick build (one shot)

```bash
docker volume create spacewar-vol
docker run -d --name spacewar-build \
  -v spacewar-vol:/work -w /work \
  kalilinux/kali-rolling sleep infinity

docker exec spacewar-build bash -c "
  apt-get update -qq && \
  apt-get install -y --no-install-recommends \
    build-essential bc bison flex libssl-dev libelf-dev libncurses-dev \
    python3 python-is-python3 git wget xz-utils zip unzip ccache rsync \
    ca-certificates curl clang lld llvm cpio kmod zstd \
    gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu \
    gcc-arm-linux-gnueabi binutils-arm-linux-gnueabi
"

# Workaround: Neutron Clang's bundled ld.lld needs libxml2.so.2;
# Kali only ships libxml2.so.16 (ABI-compatible).
docker exec spacewar-build bash -c \
  "ln -sf /usr/lib/x86_64-linux-gnu/libxml2.so.16 /usr/lib/x86_64-linux-gnu/libxml2.so.2"
```

Then copy the scripts and configs into the container and run them — see [scripts/](../scripts).

## What the build produces

- `out/arch/arm64/boot/Image` — kernel binary (~45 MB, no LTO/CFI).
- 3 out-of-tree `.ko` modules: `8188eu.ko`, `88x2bu.ko`, `8821cu.ko`.
- An AnyKernel3 zip ready to flash via Franco Kernel Manager.

## Critical config flags (do NOT change)

| Config | Value | Why |
|---|---|---|
| `CFI_CLANG` | `n` | Out-of-tree Realtek drivers crash the kernel on `iw set type monitor` when CFI is on. |
| `LTO` | `n` (LTO_NONE) | Forced off because CFI off → Kconfig dependency. Loses some optimization but runs fine. |
| `WLAN_VENDOR_REALTEK` | `n` | Avoid conflicts with our out-of-tree Realtek drivers. (We rely on QCACLD for internal Wi-Fi.) |
| `ATH9K_HTC` | `n` | Symbol conflict with QCACLD HTC layer. |
| `EXFAT_FS` | `y` | Parity with official Kali NetHunter kernel. |
| `LOCALVERSION` | `""` (empty) | Avoid the build host's Kali codename suffix (e.g. `-astatine-honeydew`) leaking into the kernel string. |

## Source patches required

These are applied automatically by `scripts/apply-patches.sh`:

1. `include/linux/haven/hh_msgq.h` — three `int`-returning stub functions had `return ERR_PTR(-EINVAL)` (returning a pointer from an int function). Fixed to `return -EINVAL`.
2. `drivers/media/platform/msm/cvp/msm_cvp_ioctl.c` — missing `#include <linux/compat.h>` (needed for `compat_ptr`).
3. Out-of-tree drivers (rtl8188eus, 88x2bu-20210702, 8821cu-20210916): Add `MODULE_IMPORT_NS(VFS_internal_I_am_really_a_filesystem_and_am_NOT_a_driver)` to `os_dep/linux/os_intfs.c`. The drivers have a `#if (LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0))` guard around it, but our kernel is 5.4 and still requires the namespace import.
4. Out-of-tree drivers: Remove `-Wno-stringop-overread` from Makefiles (not supported by older clang versions).
5. Out-of-tree drivers: Build with `KCFLAGS=-fno-stack-protector` (kernel doesn't export `__stack_chk_guard` symbol for modules in this config).

## Toolchain

[Neutron Clang 19](https://github.com/Neutron-Toolchains/clang-build-catalogue/releases/tag/10032024) is downloaded from the upstream release. ~570 MB tar.zst.

We initially tried Debian's `clang-21` from apt — it builds successfully but produces a kernel that **hangs at the Nothing logo every boot**. Neutron's kernel-tuned LLVM produces a working kernel.
