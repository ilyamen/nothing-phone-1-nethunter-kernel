# Pre-built kernel modules

Three out-of-tree Realtek Wi-Fi drivers built against this kernel (`5.4.281-NetHunter`, Neutron Clang 19, CFI off).

| Module | Size | For chipset | Adapters tested |
|---|---|---|---|
| `8188eu.ko` | ~1.8 MB | RTL8188EUS / RTL8188ETV | TP-Link TL-WN722N v3 |
| `88x2bu.ko` | ~5.6 MB | RTL8812BU / RTL8822BU | Asus USB-AC58 |
| `8821cu.ko` | ~3.6 MB | RTL8811CU / RTL8821CU | Mercusys MU-6H |

These are also packaged inside the AnyKernel3 zip in `modules/vendor/lib/modules/5.4.281-NetHunter/kernel/drivers/net/wireless/realtek/` — flashing that places them where `modprobe` finds them.

For ad-hoc loading without re-flashing the kernel:
```bash
adb push 8188eu.ko /sdcard/
adb shell 'su -c "insmod /sdcard/8188eu.ko"'
```

Vermagic must match the running kernel exactly:
```
5.4.281-NetHunter SMP preempt mod_unload modversions aarch64
```

If you're running a different kernel build, these won't load — rebuild from source instead.
