#!/system/bin/sh
# nh-batch5-storage — load NTFS + CIFS filesystem drivers.

MODDIR=${0%/*}
LOG=/cache/nh-batch5-storage.log
mkdir -p /cache 2>/dev/null

{
  echo "=== $(date) nh-batch5-storage post-fs-data ==="
  uname -r
  # NTFS standalone (read+write)
  /system/bin/insmod $MODDIR/system/lib/modules/ntfs.ko 2>&1 && echo "[+] ntfs OK" || echo "[!] ntfs FAIL"
  # CIFS needs dns_resolver first
  /system/bin/insmod $MODDIR/system/lib/modules/dns_resolver.ko 2>&1 && echo "[+] dns_resolver OK" || echo "[!] dns_resolver FAIL"
  /system/bin/insmod $MODDIR/system/lib/modules/cifs.ko 2>&1 && echo "[+] cifs OK" || echo "[!] cifs FAIL"
  echo "=== loaded ==="
  /system/bin/lsmod | grep -E 'ntfs|cifs|dns_resolver'
} >> $LOG 2>&1
