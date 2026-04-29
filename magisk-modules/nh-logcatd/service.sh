#!/system/bin/sh
# nh-logcatd v3 — late-boot persistent logcat + periodic dmesg snapshots.
# Tuned for v1.1.1 kernel: bigger printk ring (512KB), bigger pstore (4MB total),
# dmesg timestamps (CONFIG_PRINTK_TIME=y), userspace pmsg ring (512KB).
# service.d hook runs after Zygote start, when logcat is fully functional.

LOGDIR=/data/local/log
mkdir -p "$LOGDIR" 2>/dev/null

# Wait for boot to actually complete (some buffers don't init until then)
i=0
until [ "$(getprop sys.boot_completed)" = "1" ] || [ $i -gt 30 ]; do
  sleep 2
  i=$((i + 1))
done
sleep 5

# === Layer A: increase logcat ring buffers (was 8M, now 16M) ===
# v1.1.1 kernel emits more dmesg events (PRINTK_TIME timestamps + 4× larger
# kernel ring 512KB), and userspace activity is unchanged — but if logcat
# is buffer-bound during heavy events the kernel events from dmesg-bridge
# get dropped. 16M gives ~30 min of activity before old entries roll out.
logcat -G 16M 2>/dev/null

# === Layer B: persistent logcat daemon, 128MB rotating (16MB × 8 files) ===
# Up from 64MB in v2 to keep ~2× the historical window now that kernel
# emits more (still well under 600MB storage budget).
pkill -f 'logcat -f /data/local/log/logcat' 2>/dev/null

nohup logcat \
  -f "$LOGDIR/logcat.log" \
  -r 16384 -n 8 \
  -v threadtime,year,uid \
  >/dev/null 2>&1 &

# === Layer C: dmesg snapshots every 30s, hourly rotation (24 files keep) ===
# Each snapshot is now up to 512KB (was up to 128KB) due to LOG_BUF_SHIFT=19.
nohup sh -c '
  while true; do
    HH=$(date +%H)
    /system/bin/dmesg > "/data/local/log/dmesg-${HH}.log" 2>/dev/null
    chmod 644 "/data/local/log/dmesg-${HH}.log" 2>/dev/null
    sleep 30
  done
' >/dev/null 2>&1 &

# === Layer K (NEW v3.1): SELinux AVC denials watcher ===
# AVC = Access Vector Cache. When Magisk modules try to do something SELinux
# blocks, kernel emits "type=1400 audit(...) avc: denied" lines in dmesg.
# These are silent — modules just fail without obvious error message.
# This watcher polls dmesg every 60s and persists denials to a dedicated log.
# Useful for diagnosing "module installed but doesn't seem to do anything".
mkdir -p "$LOGDIR" 2>/dev/null
nohup sh -c '
  while true; do
    /system/bin/dmesg 2>/dev/null \
      | grep -E "type=1400|avc:[[:space:]]+denied|audit:[[:space:]]+type=1400" \
      | tail -200 > "/data/local/log/selinux-denials.log"
    chmod 644 "/data/local/log/selinux-denials.log" 2>/dev/null
    sleep 60
  done
' >/dev/null 2>&1 &

# === Layer I (v3): write boot marker to /dev/pmsg0 ===
# /dev/pmsg0 is the userspace half of pstore's pmsg-ramoops (512KB ring).
# Whatever we write here survives kernel panic + reboot — kernel will dump
# the ring to /sys/fs/pstore/pmsg-ramoops-0 on next boot, where post-fs-data.sh
# grabs it. So "boot marker" written here at every successful boot lets us
# know exactly when the LAST clean boot was, even if the panic prevents
# any other logging mechanism from working.
if [ -e /dev/pmsg0 ]; then
  echo "==== nh-logcatd v3 boot marker $(date '+%Y-%m-%d %H:%M:%S') kernel=$(uname -r) ====" \
    > /dev/pmsg0 2>/dev/null
fi

# Log the daemons we started
{
  echo "=== $(date) nh-logcatd service.sh ==="
  echo "boot_completed at i=$i polls"
  echo "logcat -G size:"
  logcat -g 2>&1 | head -5
  echo "running daemons:"
  ps -ef | grep -E '(logcat -f|dmesg)' | grep -v grep | head -5
} >> "$LOGDIR/nh-logcatd.log" 2>&1
