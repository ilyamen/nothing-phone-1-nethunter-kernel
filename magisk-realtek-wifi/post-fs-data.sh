#!/system/bin/sh
# Auto-load Realtek USB WiFi drivers at boot — runs after /data is mounted, before init starts services.
# Modules ship under $MODPATH/system/lib/modules but we insmod them by absolute path
# so they don't depend on /vendor/lib/modules/modules.dep regeneration.

MODDIR=${0%/*}
LOG=/cache/realtek-wifi-load.log

mkdir -p /cache 2>/dev/null

{
  echo "=== $(date) realtek-wifi-cfi-fix post-fs-data ==="
  uname -r
  for ko in 8188eu.ko 88x2bu.ko 8821cu.ko; do
    F=$MODDIR/system/lib/modules/$ko
    if [ -f "$F" ]; then
      /system/bin/insmod "$F" 2>&1 && echo "[+] insmod $ko OK" || echo "[!] insmod $ko FAIL"
    fi
  done
  echo "=== loaded modules ==="
  /system/bin/lsmod | grep -E '8188|8812|8821'
} >> $LOG 2>&1
