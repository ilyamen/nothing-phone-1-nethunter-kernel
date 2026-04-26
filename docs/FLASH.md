# Flashing the kernel

## Pre-flight: make a backup

This is not optional. If anything goes wrong you'll need to restore.

```bash
adb shell 'su -c "
  mkdir -p /sdcard/backup_$(date +%Y%m%d)
  cd /sdcard/backup_$(date +%Y%m%d)
  for p in boot_a boot_b vendor_boot_a vendor_boot_b vbmeta_a vbmeta_b vbmeta_system_a vbmeta_system_b dtbo_a dtbo_b super misc modem_a modem_b modemst1 modemst2 persist; do
    dd if=/dev/block/by-name/$p of=$p.img 2>&1 | head -1
  done
  ls -lh
"'
adb pull /sdcard/backup_YYYYMMDD ./local-backup
```

Critical files for recovery: `boot_a.img`, `boot_b.img`, `vbmeta_a.img`, `vbmeta_b.img`, `misc.img`, `modemst1.img`, `modemst2.img`.

## Flashing via Franco Kernel Manager (recommended)

1. Push the zip to phone:
   ```
   adb push spacewar-nethunter-vN-FINAL.zip /sdcard/Download/
   ```
2. Open **Franco Kernel Manager** → tap **Flasher** (or "Manual Flash" depending on version).
3. Browse to `/sdcard/Download/spacewar-nethunter-vN-FINAL.zip`.
4. Tap **"Flash & Reboot"**.
5. Wait for reboot.

AnyKernel3 (under the hood of FKM's flasher) preserves your existing ramdisk including Magisk patches. Root survives.

## Verify after reboot

```bash
adb shell uname -r
# Expected: 5.4.300-NetHunter

adb shell 'su -c "lsmod"'
# Empty initially. Modules load on demand when adapter is plugged.

adb shell 'iw phy phy0 info | grep -A3 "interface modes"'
# Should list "monitor" among supported modes (QCACLD internal Wi-Fi).
```

## Recovery if it breaks

### Bootloop / stuck on Nothing logo

1. Power off (long-press 30 sec).
2. **Power + Volume Down** to enter Fastboot Mode.
3. Connect USB. On Windows you need the [Google USB driver](https://developer.android.com/studio/run/win-usb) installed manually for `VID_18D1&PID_D00D` (Nothing Phone bootloader). See [docs/WINDOWS-FASTBOOT-DRIVER.md](WINDOWS-FASTBOOT-DRIVER.md).
4. Restore from backup:
   ```
   fastboot flash boot_a backup/boot_a.img
   fastboot flash boot_b backup/boot_b.img
   fastboot reboot
   ```

### Boots into recovery loop (OrangeFox/TWRP)

If your phone has OrangeFox installed in `boot_a` and Android in `boot_b`, make sure you're booting the right slot:
```
fastboot --set-active=b
fastboot reboot
```

You can identify which slot has Android: it'll have header v3 and an empty cmdline. The recovery slot uses header v4 with `cmdline = twrpfastboot=1` (or similar).

### Hard nuclear option

Use [spike0en/nothing_archive](https://github.com/spike0en/nothing_archive) for stock Nothing OS firmware to fully revert to factory.

## Testing the external adapters after flash

Plug in adapter via USB-C OTG (powered hub recommended for AC58 and Mercusys).

### TP-Link TL-WN722N v3
```
adb shell 'su -c "
  insmod /sdcard/Download/modules/8188eu.ko
  iw dev wlan1 set type monitor
  ip link set wlan1 up
"'
```

### Asus USB-AC58
```
adb shell 'su -c "
  insmod /sdcard/Download/modules/88x2bu.ko
  iw dev wlan1 set type monitor
  ip link set wlan1 up
"'
```

### Mercusys MU-6H
First time only — needs USB mode switch (see [MERCUSYS-USB-MODESWITCH.md](MERCUSYS-USB-MODESWITCH.md)). Then load module like the others.

For permanent persistence, install modules to `/vendor/lib/modules/5.4.300-NetHunter/` via a Magisk module overlay. The included `wirelessFirmware`-like layout in our AnyKernel3 zip already does this.
