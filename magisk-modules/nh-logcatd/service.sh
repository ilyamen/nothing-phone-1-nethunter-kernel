#!/system/bin/sh
# nh-logcatd — late-boot persistent logcat + periodic dmesg snapshots.
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

# === Layer A: increase logcat ring buffers from 256K to 8M each ===
logcat -G 8M 2>/dev/null

# === Layer B: persistent logcat daemon, 64MB rotating (8MB × 8 files) ===
# Gives ~24-48h on heavy use, ~3-7 days idle. /data has plenty of space.
pkill -f 'logcat -f /data/local/log/logcat' 2>/dev/null

nohup logcat \
  -f "$LOGDIR/logcat.log" \
  -r 8192 -n 8 \
  -v threadtime,year,uid \
  >/dev/null 2>&1 &

# === Layer C: dmesg snapshots every 30s, hourly rotation (24 files keep) ===
nohup sh -c '
  while true; do
    HH=$(date +%H)
    /system/bin/dmesg > "/data/local/log/dmesg-${HH}.log" 2>/dev/null
    chmod 644 "/data/local/log/dmesg-${HH}.log" 2>/dev/null
    sleep 30
  done
' >/dev/null 2>&1 &

# Log the daemons we started
{
  echo "=== $(date) nh-logcatd service.sh ==="
  echo "boot_completed at i=$i polls"
  echo "logcat -G size:"
  logcat -g 2>&1 | head -5
  echo "running daemons:"
  ps -ef | grep -E '(logcat -f|dmesg)' | grep -v grep | head -5
} >> "$LOGDIR/nh-logcatd.log" 2>&1
