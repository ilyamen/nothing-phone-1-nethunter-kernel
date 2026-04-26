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

# Workaround: AOSP Clang's bundled ld.lld is linked against libxml2.so.2;
# Kali only ships libxml2.so.16 (ABI-compatible). Symlink to avoid "ld.lld: error
# while loading shared libraries: libxml2.so.2".
docker exec spacewar-build bash -c \
  "ln -sf /usr/lib/x86_64-linux-gnu/libxml2.so.16 /usr/lib/x86_64-linux-gnu/libxml2.so.2"
```

Then copy the scripts and configs into the container and run them — see [scripts/](../scripts).

## What the build produces

- `out/arch/arm64/boot/Image` — kernel binary (~45 MB, no LTO/CFI).
- 3 out-of-tree `.ko` modules: `8188eu.ko`, `88x2bu.ko`, `8821cu.ko`.
- An AnyKernel3 zip ready to flash via Franco Kernel Manager.

## Source

- Repo: [`kimocoder/android_kernel_lineage_nothing_sm7325`](https://github.com/kimocoder/android_kernel_lineage_nothing_sm7325)
- Branch: `nethunter-23.0` (internal base: `android13-5.4-lahaina`)
- Linux: 5.4.300 + LineageOS upstream + ASB-2025-10 patch sets
- Defconfig: `arch/arm64/configs/spacewar_defconfig` (kimocoder's device-specific defconfig — NetHunter prerequisites pre-enabled)

## Critical config flags (do NOT change)

| Config | Value | Why |
|---|---|---|
| `CFI_CLANG` | `n` | Out-of-tree Realtek drivers crash the kernel on `iw set type monitor` when CFI is on. Defconfig ships with `=y`, we override. |
| `LTO` | `n` (LTO_NONE) | Forced off because CFI off → Kconfig dependency. Loses some optimization but runs fine. |
| `ATH9K_HTC` | `n` | Defensive: symbol conflict with QCACLD HTC layer. |
| `LOCALVERSION` | `""` (empty) | Defconfig has `"-qgki"`; we clear it so the kernel string is clean `5.4.300-NetHunter` from the env var. |

Already correct in `spacewar_defconfig`, no override needed:

| Config | Value |
|---|---|
| `WLAN_VENDOR_REALTEK` | `n` |
| `EXFAT_FS` | `y` |
| `HID`, `USB_F_HID`, `USB_F_MASS_STORAGE` | `y` |

## Source patches required

These are applied automatically by `scripts/apply-patches.sh`:

1. `include/linux/haven/hh_msgq.h` — three `int`-returning stub functions had `return ERR_PTR(-EINVAL)` (returning a pointer from an int function). Fixed to `return -EINVAL`.
2. `drivers/media/platform/msm/cvp/msm_cvp_ioctl.c` — missing `#include <linux/compat.h>` (needed for `compat_ptr`).
3. Out-of-tree drivers (rtl8188eus, 88x2bu-20210702, 8821cu-20210916): Add `MODULE_IMPORT_NS(VFS_internal_I_am_really_a_filesystem_and_am_NOT_a_driver)` to `os_dep/linux/os_intfs.c`. The drivers have a `#if (LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0))` guard around it, but our kernel is 5.4 and still requires the namespace import.
4. Out-of-tree drivers: Remove `-Wno-stringop-overread` from Makefiles (not supported by older clang versions).
5. Out-of-tree drivers: Build with `KCFLAGS=-fno-stack-protector` (kernel doesn't export `__stack_chk_guard` symbol for modules in this config).

## Toolchain

**AOSP Clang `r536225`** (Clang 18.0.4, Google's kernel-tuned prebuilt) — same toolchain kimocoder uses in his official [`build.sh`](https://raw.githubusercontent.com/kimocoder/kernel_nothing_sm7325/nethunter-15.0/build.sh):

```bash
MAKE_PARAMS="O=out ARCH=arm64 CC=clang CLANG_TRIPLE=clang LLVM=1 LLVM_IAS=1 \
    CROSS_COMPILE=aarch64-linux-gnu-"
```

Downloaded from `SA9990/Toolchain` GitHub mirror (avoids AOSP googlesource throttling) with fallback to AOSP `prebuilts/clang/host/linux-x86 +archive/refs/heads/main-kernel/clang-r536225.tar.gz`. ~280 MB tar.gz.

Earlier iterations of this build tried Debian's `clang-21` (kernel hangs at Nothing logo) and Neutron Clang 19 (works, but not the canonical Android-team toolchain). Switched to AOSP Clang r536225 to match kimocoder's recipe exactly — proven to boot.
