# Mercusys MU-6H — USB Mode Switch quirk

The Mercusys MU-6H ships in a dual-mode USB descriptor. On first power-up it presents itself as a **CD-ROM device with PID `0bda:1a2b`** (containing the Windows driver installer). It needs to be told to switch to its **Wi-Fi mode (`0bda:c811`)** before any wireless driver can claim it.

## Symptom

After plugging in:
```
$ lsusb | grep 0bda
Bus 002 Device 004: ID 0bda:1a2b
```
No `wlan1` interface appears. Loading `8821cu.ko` doesn't help — the driver only matches Wi-Fi PIDs (`B82B`, `B820`, `C821`, `C820`, `C82A`, `C82B`, `C811`, `8811`, `2006`, `8731`).

## Fix

Install `usb-modeswitch` in your Kali chroot (it's not on Android side). It's already in Kali's default install but verify:

```
chroot /data/local/nhsystem/kali-arm64 apt-get install -y usb-modeswitch
```

Then send the mode-switch:

```bash
adb shell 'su -c "
  ROOT=/data/local/nhsystem/kali-arm64
  mount --bind /dev \$ROOT/dev
  mount --bind /sys \$ROOT/sys
  chroot \$ROOT /usr/sbin/usb_modeswitch -v 0bda -p 1a2b -K
"'
```

The `-K` flag sends the standard Huawei-style switch message which works for this Realtek variant.

After this, the device re-enumerates as `0bda:c811` and `wlan1` appears (if `8821cu.ko` is loaded). Now you can:

```
iw dev wlan1 set type monitor
ip link set wlan1 up
```

## Persistent solution

Add a udev rule (in chroot or a Magisk overlay) so the switch fires automatically on plug-in:

```
# /etc/udev/rules.d/40-mercusys-mu6h.rules
ATTR{idVendor}=="0bda", ATTR{idProduct}=="1a2b", RUN+="/usr/sbin/usb_modeswitch -v 0bda -p 1a2b -K"
```

(Doesn't work without udev running, which on Android isn't the default. A more reliable Android-side approach is a Magisk service script that polls `lsusb` and switches when it sees `1a2b`.)

## Why Realtek does this

Marketing reasons — when end-users plug the adapter into Windows for the first time, Windows mounts the CD-ROM and prompts to install the bundled driver. Once installed, the Windows driver knows to flip to Wi-Fi mode. On Linux/Android we have to do that manually.

A "real" fix would be patching the kernel `usb-storage` driver with a quirk for `0bda:1a2b` to refuse the storage interface and allow the wireless one through. We didn't bother because the userspace mode switch is fast and one-line.
