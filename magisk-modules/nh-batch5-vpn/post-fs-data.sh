#!/system/bin/sh
# nh-batch5-vpn — load WireGuard + its crypto dependencies in correct order.

MODDIR=${0%/*}
LOG=/cache/nh-batch5-vpn.log
mkdir -p /cache 2>/dev/null

{
  echo "=== $(date) nh-batch5-vpn post-fs-data ==="
  uname -r
  for ko in chacha-neon.ko poly1305-neon.ko libcurve25519-generic.ko libcurve25519.ko libchacha20poly1305.ko wireguard.ko; do
    F=$MODDIR/system/lib/modules/$ko
    if [ -f "$F" ]; then
      /system/bin/insmod "$F" 2>&1 && echo "[+] $ko OK" || echo "[!] $ko FAIL"
    fi
  done
  echo "=== loaded ==="
  /system/bin/lsmod | grep -E 'wireguard|chacha|poly1305|curve25519'
} >> $LOG 2>&1
