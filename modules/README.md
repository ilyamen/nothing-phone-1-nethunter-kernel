# Pre-built kernel modules — `5.4.302-qgki-g192e5b024436-dirty`

Three out-of-tree Realtek Wi-Fi drivers built against the **Stage 4 NetHunter kernel** running on the phone (slot_a). Verified working — `iw set type monitor` + tcpdump + aireplay-ng all without kernel panic.

| Module | Size | Chipset | Adapter tested |
|---|---|---|---|
| `8188eu.ko` | 2.0 MB | RTL8188EUS / RTL8188ETV | TP-Link TL-WN722N v3 ✅ field-tested |
| `88x2bu.ko` | 6.2 MB | RTL8812BU / RTL8822BU | Asus USB-AC58 ⏳ built only |
| `8821cu.ko` | 4.2 MB | RTL8811CU / RTL8821CU | Mercusys MU-6H ⏳ built only |

## Vermagic

```
5.4.302-qgki-g192e5b024436-dirty SMP preempt mod_unload modversions aarch64
```

If your running kernel reports a different vermagic, these `.ko` won't load — rebuild via `scripts/06-build-modules.sh`.

Verify on phone:

```bash
adb shell uname -r
# expected → 5.4.302-qgki-g192e5b024436-dirty
```

## CFI signature fix

These modules embed the [PR #1041](https://github.com/aircrack-ng/rtl8812au/pull/1041) CFI signature fix by GeorgeBannister. Without that fix, `iw dev wlan1 set type monitor` would kernel-panic on a CFI=on kernel (which our build requires).

See [`../docs/CFI-FIX.md`](../docs/CFI-FIX.md) for the full story.

## Loading

### Ad-hoc

```bash
adb push 8188eu.ko /data/local/tmp/
adb shell 'su -c "insmod /data/local/tmp/8188eu.ko"'
# Plug WN722N into OTG, wlan1 should appear
```

### Persistent (Magisk module — recommended)

Already packaged at `../output/realtek-wifi-cfi-fix-v1.0.zip`. Auto-loads all 3 on every boot via `post-fs-data.sh`. Install:

```bash
adb push ../output/realtek-wifi-cfi-fix-v1.0.zip /sdcard/Download/
adb shell "su -c 'magisk --install-module /sdcard/Download/realtek-wifi-cfi-fix-v1.0.zip && \
                  unzip -o /sdcard/Download/realtek-wifi-cfi-fix-v1.0.zip \
                        -d /data/adb/modules/realtek-wifi-cfi-fix -x META-INF/*'"
adb reboot
```

(The manual `unzip` after `magisk --install-module` is a workaround — see `../docs/BUILD-LOG-2026-04-26.md` Bug 17.)

## Source patches

The CFI fix is applied by `scripts/03-apply-patches.sh` automatically. If you need to inspect/replay the diffs by hand, they're in `../artifacts/realtek-patches/`:

```
artifacts/realtek-patches/rtl8188eus-cfi-fix.patch
artifacts/realtek-patches/88x2bu-20210702-cfi-fix.patch
artifacts/realtek-patches/8821cu-20210916-cfi-fix.patch
```
