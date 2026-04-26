# Diagnostic story — what we tried and what we learned

This is a brain-dump of the debugging journey from "first build hangs at boot" to "everything works." Useful if you're debugging similar issues with a custom Android kernel.

## Tested device

- Phone: Nothing Phone 1 (codename `spacewar`, model A063)
- ROM: AOSPA Topaz 9 (Android 13, build `topaz-9-phone1-20230916`)
- Stock kernel installed: `5.4.256-NetHunter` built by `cr4sh@parrot` (third-party, no source published)
- Existing root: Magisk 30.7

## Issues encountered (in order)

### 1. `xt_DSCP.c` not found — Docker on Windows case-insensitivity

**Symptom:** Build fails with `No rule to make target 'net/netfilter/xt_DSCP.o'`.

**Root cause:** Both `xt_DSCP.c` (uppercase, target module) and `xt_dscp.c` (lowercase, match module) exist in the Linux kernel source. NTFS on Windows is case-insensitive — when Docker bind-mounts the source from `C:\spacewar-build\`, only one file survives.

**Fix:** Use a Docker named volume (`docker volume create spacewar-vol`) instead of bind-mount. Volumes live on the Linux side and are case-sensitive.

### 2. `unknown warning option '-Wno-enum-enum-conversion'` — Clang too old

**Symptom:** Initial build with Google's `clang-10.0.4` fails on a modern kernel flag.

**Fix:** Use a newer Clang. We initially went with Debian's `clang-21` from apt — built fine, but produced a non-bootable kernel (see #5). Eventually settled on **Neutron Clang 19** (LLVM 17/18-derived, kernel-tuned).

### 3. `linux/wlan_plat.h: file not found` — Realtek out-of-tree drivers

**Symptom:** Building `rtl8188eus`/`88x2bu`/`8821cu` modules fails with missing Android-WLAN-platform header.

**Fix:** Remove `-DRTW_ENABLE_WIFI_CONTROL_FUNC` from the driver Makefiles (only needed on full Android with WiFi HAL).

### 4. `Must be LITTLE or BIG Endian` — driver Makefile wrong

**Symptom:** `rtl8188eus` driver build fails with `ODM_ENDIAN_TYPE` undefined.

**Fix:** The Makefile's `CONFIG_PLATFORM_ANDROID_ARM64` block doesn't define `CONFIG_LITTLE_ENDIAN`. We added an explicit ifeq block setting both `CONFIG_LITTLE_ENDIAN` and `CONFIG_PLATFORM_ANDROID` for the `ANDROID_ARM64` platform.

### 5. Kernel hangs at Nothing logo — wrong toolchain

**Symptom:** First build with Debian's `clang-21` produces a kernel that boots through the bootloader, shows the Nothing logo, and freezes. No pstore log captured because pstore isn't initialized that early.

**Diagnosis:** Compared the working `cr4sh@parrot` kernel to ours. He used Google's AOSP Clang 17 with PGO/BOLT/LTO/MLGO optimizations. Generic distro Clang produces subtly different code that the device firmware doesn't like.

**Fix:** Switched to **Neutron Clang 19** (a kernel-tuned LLVM build maintained by the Android kernel-builder community).

### 6. Kernel reverts to X86 config silently

**Symptom:** Halfway through iteration, builds suddenly stop including ARM64 features, kernel hangs at boot. `grep CONFIG_ARM64 .config` returns nothing; `CONFIG_X86_DIRECT_GBPAGES=y` appears.

**Root cause:** Running `make olddefconfig` without `ARCH=arm64` set in the environment defaults to host architecture (x86_64) and silently rewrites the entire config.

**Fix:** Always pass `ARCH=arm64` explicitly when invoking any `make` target on the kernel, including `olddefconfig`. The `scripts/config` tool doesn't need ARCH (it just edits the file), but `olddefconfig` does.

### 7. We backed up the wrong slot's boot.img

**Symptom:** After flashing kernel and rebooting, every boot lands in OrangeFox recovery instead of Android. We try restoring from `boot_a.img` backup — still recovery loop.

**Root cause:** User was on slot `b` when we made the backup. `boot_a.img` we backed up from the inactive slot was actually OrangeFox recovery (cmdline: `twrpfastboot=1`, header v4). The real Android Magisk-patched kernel was in `boot_b.img` (cmdline: empty, header v3, OS version 13.0.0).

**Fix:** Always identify which slot is active before backing up. Always back up BOTH slots and inspect their cmdline / OS version with `unpack_bootimg.py` to know which is which. To switch active slot in fastboot: `fastboot --set-active=b`.

### 8. `bootloader fastboot` driver missing on Windows

**Symptom:** Phone in Fastboot Mode shows up in Device Manager as "Android" with status `Error`. `fastboot devices` returns empty. PID is `D00D` which isn't in Google's stock `android_winusb.inf`.

**Fix:** Manually install Google USB Driver via Device Manager → "Update driver" → "Browse my computer" → "Let me pick from a list" → "Have Disk" → point to `android_winusb.inf` → choose "Android Bootloader Interface" from the list. Windows allows manual driver binding to any device even if PID doesn't match. The signed `.cat` file remains valid because we don't modify the `.inf`.

### 9. `--disable-verity --disable-verification` made things WORSE

**Symptom:** During recovery from a bad flash, ran `fastboot --disable-verity --disable-verification flash vbmeta_a vbmeta.img`. After this, every reboot still went into recovery — even with a known-good kernel.

**Root cause:** The flag modifies the vbmeta header before flashing. The interaction with our specific phone state (Magisk + AOSPA + custom recovery) caused permanent recovery boot.

**Fix:** Re-flash vbmeta byte-for-byte from backup (no `--disable-*` flags). And restore `misc` partition from backup instead of erasing it (erasing misc can leave stale boot-mode flags on some devices).

### 10. Module load fails — `kernel_read` from VFS_internal namespace

**Symptom:** After successful kernel boot, `insmod 8188eu.ko` fails with `Unknown symbol kernel_read (err -22)`.

**Root cause:** Linux 5.4 (and 5.10+) put VFS file functions like `kernel_read`, `kernel_write`, `kern_path` into a namespace called `VFS_internal_I_am_really_a_filesystem_and_am_NOT_a_driver`. Drivers using these need `MODULE_IMPORT_NS(VFS_internal_I_am_really_a_filesystem_and_am_NOT_a_driver)`. The Realtek out-of-tree drivers have this only inside `#if (LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0))` — but our 5.4 kernel still requires it.

**Fix:** Patch `os_dep/linux/os_intfs.c` of all 3 Realtek drivers to make `MODULE_IMPORT_NS` unconditional. Sed-script is in `scripts/apply-patches.sh`.

### 11. Module load fails — `__stack_chk_guard` undefined

**Symptom:** `Unknown symbol __stack_chk_guard (err -22)` when loading freshly built modules.

**Root cause:** Kernel built with stack protector enabled (`STACKPROTECTOR_STRONG=y`) but the symbol isn't exported for module use in this build configuration.

**Fix:** Build the modules with `KCFLAGS=-fno-stack-protector` so they don't reference the canary.

### 12. **THE BIG ONE** — kernel panics on `iw set type monitor`

**Symptom:** `iw dev wlan1 set type monitor` instantly hangs the kernel. Phone reboots. No pstore log (panic too early or buffer overflow from haptics spam).

**Root cause:** **CFI (Control Flow Integrity)** is enabled (`CONFIG_CFI_CLANG=y`) in our config. CFI validates function pointer call sites against expected signatures. Out-of-tree Realtek drivers do indirect calls into mac80211 callbacks with signatures CFI doesn't recognize → CFI immediately panics. This is a [known issue](https://github.com/aircrack-ng/rtl8812au/issues/1201) affecting `rtl8812au`, `rtl8188eus`, `88x2bu`, `8821cu` — basically all out-of-tree Realtek drivers.

The working `cr4sh@parrot` kernel works because it has `CONFIG_CFI_CLANG` not set.

**Fix:** Disable `CONFIG_CFI_CLANG` and `CONFIG_CFI_CLANG_SHADOW`. As a side-effect Kconfig also forces `LTO_NONE=y` (CFI requires LTO; with CFI off, the choice block defaults LTO to NONE). Build is ~5% larger and arguably ~5% slower without LTO, but everything works.

### 13. Mercusys MU-6H stays in CD-ROM mode

**Symptom:** `lsusb` shows `0bda:1a2b` (CD-ROM/installer mode). No `wlan1` despite driver being loaded.

**Fix:** Run `usb_modeswitch -v 0bda -p 1a2b -K` from Kali chroot to flip the device into Wi-Fi mode. Details in [MERCUSYS-USB-MODESWITCH.md](MERCUSYS-USB-MODESWITCH.md).

## Lessons

- **Always test toolchain compatibility separately.** A kernel that builds successfully isn't necessarily a kernel that boots. Try the toolchain on a known-good source first if possible.
- **CFI is hostile to out-of-tree drivers.** If you're building a kernel for an Android device that needs out-of-tree Realtek/MediaTek/Atheros drivers, just disable CFI from the start.
- **Always identify slot orientation before flashing.** A/B partition layout is non-obvious; the inactive slot can hold completely different content (recovery vs Android).
- **Always pass `ARCH=` explicitly.** Even seemingly-innocuous `make olddefconfig` will silently corrupt your config.
- **Make backups of vbmeta and misc, not just boot.** And don't blindly use `--disable-verity` — it modifies vbmeta in ways that can cascade into recovery loops.
- **Pstore is too small for noisy devices.** This Nothing Phone 1 has a chatty haptics driver that fills the 213 KB ramoops buffer in seconds. To debug late-boot panics you may need to either disable the haptics module or increase `CONFIG_PSTORE_RAM_SIZE`.

## Migration: XOS-14.0.2 → lineage nethunter-23.0 (2026-04)

The original v1 build used `kimocoder/kernel_nothing_sm7325` branch `XOS-14.0.2` (Linux 5.4.281, XOS ROM lineage) with Neutron Clang 19 and the monolithic `vendor/lahaina-qgki_defconfig`. Replaced with `kimocoder/android_kernel_lineage_nothing_sm7325` branch `nethunter-23.0` (Linux 5.4.300, LineageOS upstream + ASB security patches) for these reasons:

1. **Source maintenance** — XOS-14.0.2 hadn't been updated since 2024-08; lineage nethunter-23.0 actively pulls LineageOS upstream merges (e.g. `ASB-2025-10-06_11-5.4` → Linux 5.4.300) and has an explicit commit `qcacld: enable direct monitor mode through 'iw'`.
2. **Defconfig** — switched to kimocoder's purpose-built `arch/arm64/configs/spacewar_defconfig`. It already has `CONFIG_HID=y`, `CONFIG_USB_F_HID=y`, `CONFIG_USB_F_MASS_STORAGE=y`, `CONFIG_EXFAT_FS=y` enabled — no `extras.config` fragment needed any more.
3. **Toolchain** — switched from Neutron Clang 19 to **AOSP Clang `r536225`** (Clang 18.0.4) to match kimocoder's official `build.sh` recipe exactly (`LLVM=1 LLVM_IAS=1 CC=clang CLANG_TRIPLE=clang CROSS_COMPILE=aarch64-linux-gnu-`). Downloaded from `SA9990/Toolchain` GitHub mirror with fallback to AOSP googlesource.
4. **AnyKernel3** — switched from the official Kali 2.5 GB zip download to `kimocoder/AnyKernel3` branch `spacewar` (small, purpose-built for this device, supports Android 11–16).
5. **Removed** `-d ARCH_LAHAINA -d ARCH_SHIMA` from configure step — that disable was wrong (lahaina IS the SoC family) and `spacewar_defconfig` correctly enables both. The previous build apparently worked because Kconfig dependencies forced them back on regardless.

Patches that survived the migration unchanged: `hh_msgq.h`, `msm_cvp_ioctl.c`, all three Realtek `.ko` Makefile fixes. Same upstream bugs are still present in the lineage source.

Devicetree compat: `spacewar_defconfig` keeps `CONFIG_LOCALVERSION="-qgki"`; we override to empty so the kernel string is clean `5.4.300-NetHunter`. The lineage kernel base is `android13-5.4-lahaina` (kernel base, not userland) — boots on AOSPA Topaz / Tiramisu / Uvite, LineageOS 20+, and other Android 13+ ROMs unchanged. Vendor blob ABI is consistent within the 5.4 vendor kernel family.

## Gap analysis vs official Kali NetHunter (and our fixes)

While reviewing what `kali-nethunter-kernel-builder` does at build time we found that two classes of NetHunter functionality are **not pre-baked** into kimocoder's source — they're applied during the Kali build pipeline. We replicate that here so we don't lose feature parity.

### 1. QCACLD-3.0 packet injection patch series (17 patches)

Lives in `kali-nethunter-kernel-builder/patches/5.4/add-qcacld-3.0-injection-5.4.patch` (13 861 lines, signed `kimocoder@aircrack-ng.org`, dated 2025-10-31 → 2025-11-09). It:

- Adds `case QDF_MONITOR_MODE` to `hdd_is_client_mode`/`hdd_is_ap_mode` (patch 01/17)
- Adds whole new files: `wlan_hdd_frame_inject.{c,h}`, `wlan_hdd_frame_validate.{c,h}`, `wlan_hdd_inject_security.{c,h}`, `wlan_hdd_frame_inject_*.{c,h}` (debug, security_test, integration, comprehensive_test), `wma_frame_inject.c`
- Wires `CONFIG_FEATURE_FRAME_INJECTION_SUPPORT := y` into `drivers/staging/qcacld-3.0/configs/default_defconfig` and the matching Kbuild rules
- Adds VDEV_START switching, channel width refactor, packet inject vendor command alignment

Of the 17 patches **only patch 02/17** (`qcacld: enable direct monitor mode through 'iw'`) is cherry-picked into `kimocoder/android_kernel_lineage_nothing_sm7325 nethunter-23.0`. The remaining 16 must be applied at build time — without them internal Wi-Fi (`wlan0`) can RX in monitor mode but cannot TX-inject packets.

`scripts/02-clone-sources.sh` clones the kali-nethunter-kernel-builder repo, and `scripts/03-apply-patches.sh` applies the series via `git am --3way` (with `--skip` loop for the already-applied patch 02). External Realtek `.ko` modules already do their own injection — this gap only affects users who want to attack via the internal Qualcomm radio without an external adapter.

### 2. Defconfig flags missing from `spacewar_defconfig`

`spacewar_defconfig` is comprehensive but doesn't enable a few things Kali's `devices.yml` claims for spacewar (`NFS`, etc.) or that pentest tooling expects. We force them on via `scripts/config -e ...` in `04-configure.sh`:

| Flag | Why |
|---|---|
| `CONFIG_NFS_FS`, `CONFIG_NFS_V3`, `CONFIG_NFS_V4`, `CONFIG_NFSD`, `CONFIG_NFSD_V3`, `CONFIG_NFSD_V4` | NFS client + server. `devices.yml` lists `NFS` as a spacewar feature. |
| `CONFIG_USBIP_CORE`, `CONFIG_USBIP_VHCI_HCD` | USB-over-IP forwarding — useful for sharing host-side USB devices with the phone over network (advanced pentest scenarios). |
| `CONFIG_PACKET_DIAG` | AF_PACKET socket introspection — used by `ss`, `bettercap` and similar tools that enumerate raw sockets. |

### 3. What we **don't** add (and why)

- `CONFIG_RTL8XXXU` / in-tree RTL88XXAU — Kali's `devices.yml` lists `RTL88XXAU` as a feature. We skip it because our 3 out-of-tree `.ko` modules (`rtl8188eus`, `88x2bu`, `8821cu`) cover **more chipsets** with monitor + injection. Adding the in-tree driver would just create symbol conflicts.
- `CONFIG_BT_HCIUART_QCA` — internal Bluetooth on this device goes via Qualcomm's vendor BT path, not the generic `hci_uart_qca`. Enabling it doesn't add functionality.
- `CONFIG_MAC80211_HWSIM` — Wi-Fi simulator, debug-only, not a NetHunter feature.
