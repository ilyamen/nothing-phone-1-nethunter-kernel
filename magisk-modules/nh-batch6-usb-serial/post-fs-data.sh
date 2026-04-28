#!/system/bin/sh
# nh-batch6-usb-serial — load USB Serial / ACM / cellular USB / printer host drivers.
# usbserial.ko is the framework; load it first, then specific chip drivers.

MODDIR=${0%/*}
LOG=/cache/nh-batch6-usb-serial.log
mkdir -p /cache 2>/dev/null

{
  echo "=== $(date) nh-batch6-usb-serial post-fs-data ==="
  uname -r
  # framework first, then chip drivers
  # Order matters: usbserial framework first, then usb_wwan (needed by option/qcserial),
  # then chip drivers, then non-serial USB devices.
  for ko in usbserial.ko usb_wwan.ko ftdi_sio.ko ch341.ko pl2303.ko cp210x.ko option.ko qcserial.ko cdc-acm.ko huawei_cdc_ncm.ko qmi_wwan.ko usblp.ko; do
    F=$MODDIR/system/lib/modules/$ko
    if [ -f "$F" ]; then
      /system/bin/insmod "$F" 2>&1 && echo "[+] $ko OK" || echo "[!] $ko FAIL"
    fi
  done
  echo "=== loaded ==="
  /system/bin/lsmod | grep -E 'usbserial|ftdi_sio|ch341|pl2303|cp210x|^option|qcserial|cdc_acm|huawei_cdc_ncm|qmi_wwan|usblp'
} >> $LOG 2>&1
