# Backup snapshot — 2026-04-27 18:22

Clean partition backup of Nothing Phone 1 (spacewar / A063) running LineageOS 23.2 + Magisk 30.7. Snapshot taken from **LineageOS recovery** (partitions unmounted, no in-flight writes).

## Contents

- 88 partition images, **7.9 GB total**
- Excluded: `userdata` (personal data, not needed for recovery), `sda-sdf` (whole-disk aliases), `vendor_boot_*` (taken via `fastboot fetch` before recovery boot — also in this folder).

## How to fully restore the phone

If the phone bootloops or is bricked:

```bash
adb reboot bootloader        # or: power + vol-down to enter fastboot manually

# Restore everything from this backup directory:
cd <this-folder>
for f in *.img; do
  p="${f%.img}"
  case "$p" in
    sd[a-f]|userdata) continue ;;
  esac
  echo "Flashing $p..."
  fastboot flash "$p" "$f"
done

fastboot reboot
```

## Critical files (smallest set for boot recovery)

If only the kernel is broken (most common case):

```bash
fastboot flash boot_a       boot_a.img
fastboot flash boot_b       boot_b.img
fastboot flash vendor_boot_a vendor_boot_a.img
fastboot flash vendor_boot_b vendor_boot_b.img
fastboot flash vbmeta_a     vbmeta_a.img
fastboot flash vbmeta_b     vbmeta_b.img
fastboot flash dtbo_a       dtbo_a.img
fastboot flash dtbo_b       dtbo_b.img
fastboot reboot
```

If radio is broken (no signal / cellular):

```bash
fastboot flash modem_a    modem_a.img
fastboot flash modem_b    modem_b.img
fastboot flash modemst1   modemst1.img
fastboot flash modemst2   modemst2.img
fastboot reboot
```

If sensors / WiFi mac / device-unique data lost:

```bash
fastboot flash persist persist.img
fastboot reboot
```

If everything goes catastrophically wrong:

```bash
# Flash super (6GB — system + vendor + product + odm + system_ext)
fastboot reboot fastboot     # → fastbootd userspace mode (needed for super)
fastboot flash super super.img
fastboot reboot
```

## How this backup was made

1. `adb reboot recovery` (LineageOS 23.2 recovery has root ADB by default)
2. From recovery shell: `dd if=/dev/block/by-name/<partition>` streamed via `adb exec-out` directly to host file
3. `vendor_boot_a/b` were captured separately via `fastboot fetch` from bootloader mode (the only partitions Phone 1 bootloader allows fetch on, per Nothing's hardcoded policy)

Recovery-mode dd gives a fully consistent snapshot — partitions are unmounted, no journal in-flight, no userspace writes. Same as cr4sh/morrownr-grade backup.

## Free space tip

This backup is **7.9 GB**. If you want to keep it long-term but reduce size, gzip the larger images:

```bash
gzip super.img logdump.img modem_*.img dsp_*.img boot_*.img vendor_boot_*.img dtbo_*.img
# To restore: gunzip -c <file>.img.gz | fastboot flash <partition> -
```

`super.img` compresses to ~3-4 GB (it's a sparse ext4 image).
