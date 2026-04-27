#!/data/data/com.termux/files/usr/bin/bash
# Restore internal wlan0 back to STA mode (con_mode=0) — return WiFi network.

echo "==> Internal wlan0 → STA mode (con_mode=0, normal WiFi)"

if [ "$(su -c 'cat /sys/module/wlan/parameters/con_mode 2>/dev/null')" = "0" ]; then
  echo "[~] Already in STA mode."
  su -c 'iw dev wlan0 info | head -6'
  exit 0
fi

su -c "
  ip link set wlan0 down 2>/dev/null
  rmmod wlan
  sleep 1
  insmod /data/local/tmp/wlan.ko con_mode=0
  svc wifi enable
  sleep 6
"

echo
echo "==> wlan0 state:"
su -c "iw dev wlan0 info | head -6"
echo
echo "==> WiFi should now reconnect to saved network."
