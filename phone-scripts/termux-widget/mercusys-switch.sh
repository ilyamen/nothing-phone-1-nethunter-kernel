#!/data/data/com.termux/files/usr/bin/bash
# Mercusys MU-6H — switch from CD-ROM mode (0bda:1a2b) to WiFi mode (0bda:c811)
# Run after plugging the adapter into USB-OTG. Requires Magisk root + Kali chroot
# with `usb-modeswitch` package installed.

echo "==> Mercusys USB mode switch (CD-ROM → WiFi)"

# Check if already in WiFi mode
if su -c "lsusb | grep -q '0bda:c811'"; then
  echo "[~] Already in WiFi mode (0bda:c811) — nothing to do."
  echo "    Driver should have created wlan1. Check with:"
  echo "      su -c 'ip link | grep wlan1'"
  exit 0
fi

# Check that adapter is in CD-ROM mode
if ! su -c "lsusb | grep -q '0bda:1a2b'"; then
  echo "[!] Mercusys MU-6H not detected (no 0bda:1a2b in lsusb)."
  echo "    Plug the adapter into USB-OTG and re-run."
  su -c "lsusb"
  exit 1
fi

# Run usb_modeswitch via Kali chroot
su -c "chroot /data/local/nhsystem/kali-arm64 /usr/sbin/usb_modeswitch -v 0bda -p 1a2b -K" 2>&1 | tail -3

sleep 3

echo
echo "==> Result:"
su -c "lsusb | grep -E '0bda|2357|0b05'"
echo
echo "==> Interfaces:"
su -c "ip link | grep wlan"
