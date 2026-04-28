#!/system/bin/sh
# nh-batch5-net-extras — USB CDC family + PPP/L2TP extras.

MODDIR=${0%/*}
LOG=/cache/nh-batch5-net-extras.log
mkdir -p /cache 2>/dev/null

{
  echo "=== $(date) nh-batch5-net-extras post-fs-data ==="
  uname -r
  # USB CDC: cdc-wdm and cdc_ncm have no .ko deps; cdc_mbim depends on both.
  for ko in cdc-wdm.ko cdc_ncm.ko cdc_mbim.ko cdc_eem.ko ppp_async.ko ppp_synctty.ko l2tp_ip.ko l2tp_eth.ko; do
    F=$MODDIR/system/lib/modules/$ko
    if [ -f "$F" ]; then
      /system/bin/insmod "$F" 2>&1 && echo "[+] $ko OK" || echo "[!] $ko FAIL"
    fi
  done
  echo "=== loaded ==="
  /system/bin/lsmod | grep -E 'cdc_|cdc-wdm|ppp_async|ppp_synctty|l2tp_'
} >> $LOG 2>&1
