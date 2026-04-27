#!/data/data/com.termux/files/usr/bin/bash
# Switch internal wlan0 (Qualcomm WCN6855) into monitor mode via con_mode=4 reload.
# Requires our Kali QCACLD inject patches in kernel + matching wlan.ko at
# /data/local/tmp/wlan.ko.

echo "==> Internal wlan0 → MONITOR mode (con_mode=4)"

if [ "$(su -c 'cat /sys/module/wlan/parameters/con_mode 2>/dev/null')" = "4" ]; then
  echo "[~] Already in monitor mode."
  su -c 'iw dev wlan0 info | head -8'
  exit 0
fi

if ! su -c '[ -f /data/local/tmp/wlan.ko ]'; then
  echo "[!] /data/local/tmp/wlan.ko missing — push it from PC first:"
  echo "    adb push output/wlan/wlan.ko /data/local/tmp/wlan.ko"
  exit 1
fi

su -c "
  svc wifi disable
  sleep 2
  ip link set wlan0 down 2>/dev/null
  rmmod wlan
  sleep 1
  insmod /data/local/tmp/wlan.ko con_mode=4
  svc wifi enable
  sleep 6
  ip link set wlan0 up
"

echo
echo "==> Verify:"
su -c "iw dev wlan0 info | head -8"
echo
echo "Set channel and capture:"
echo "  su -c 'iw dev wlan0 set channel 6'"
echo "  su -c 'tcpdump -i wlan0 -nn'"
