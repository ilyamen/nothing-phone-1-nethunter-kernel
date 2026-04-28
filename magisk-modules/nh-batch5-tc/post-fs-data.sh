#!/system/bin/sh
# nh-batch5-tc — TC traffic control actions + BPF classifier.

MODDIR=${0%/*}
LOG=/cache/nh-batch5-tc.log
mkdir -p /cache 2>/dev/null

{
  echo "=== $(date) nh-batch5-tc post-fs-data ==="
  uname -r
  # cls_bpf is already built-in (=y in running-config), no .ko needed
  for ko in act_bpf.ko act_mirred.ko act_nat.ko act_pedit.ko; do
    F=$MODDIR/system/lib/modules/$ko
    if [ -f "$F" ]; then
      /system/bin/insmod "$F" 2>&1 && echo "[+] $ko OK" || echo "[!] $ko FAIL"
    fi
  done
  echo "=== loaded ==="
  /system/bin/lsmod | grep -E 'cls_bpf|act_'
} >> $LOG 2>&1
