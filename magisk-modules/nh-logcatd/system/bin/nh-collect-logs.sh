#!/system/bin/sh
# nh-collect-logs — bundle recent NetHunter / kernel / Magisk logs into a tarball
# in /sdcard/Download/ for easy adb-pull retrieval.
#
# Usage:  su -c nh-collect-logs        (collect last 60 min)
#         su -c 'nh-collect-logs 360'  (last 6 hours)

MINUTES="${1:-60}"
LOGDIR=/data/local/log
STAMP=$(date +%Y%m%d-%H%M%S)

# Prefer /sdcard/Download (visible in file managers), fall back to
# /data/local/tmp (always writable, even when FBE-locked).
if [ -d /sdcard/Download ] && [ -w /sdcard/Download ] 2>/dev/null; then
  OUT="/sdcard/Download/nh-logs-${STAMP}.tar.gz"
else
  OUT="/data/local/tmp/nh-logs-${STAMP}.tar.gz"
fi

# Collect into a tmpfs staging dir
STAGE=/data/local/tmp/nh-logs-stage
rm -rf "$STAGE" && mkdir -p "$STAGE/saved"

# Just copy ALL contents of /data/local/log/ — typical size is under 50MB anyway
# and we already have rotation that keeps it bounded.
# (BusyBox find -mmin is unreliable on Android; flat copy is more robust.)
cp -r "$LOGDIR"/. "$STAGE/saved/" 2>/dev/null

# Also include CURRENT live logs unconditionally
mkdir -p "$STAGE/live"
logcat -d -v threadtime,year,uid > "$STAGE/live/logcat-current.log" 2>/dev/null
dmesg > "$STAGE/live/dmesg-current.log" 2>/dev/null

# Magisk daemon log (if exists)
[ -f /cache/magisk.log ] && cp /cache/magisk.log "$STAGE/live/" 2>/dev/null
[ -f /data/adb/magisk.log ] && cp /data/adb/magisk.log "$STAGE/live/" 2>/dev/null

# Module list snapshot
ls /data/adb/modules > "$STAGE/live/magisk-modules.txt" 2>/dev/null
lsmod > "$STAGE/live/lsmod.txt" 2>/dev/null
uname -a > "$STAGE/live/uname.txt" 2>/dev/null
getprop > "$STAGE/live/getprop.txt" 2>/dev/null

# v3: pstore live snapshot (NOT cleared — kernel will clear on next boot grab).
# Useful when collecting logs WHILE the issue is fresh, before next reboot.
mkdir -p "$STAGE/live/pstore-live"
if [ -d /sys/fs/pstore ]; then
  for f in /sys/fs/pstore/*; do
    [ -e "$f" ] || continue
    cp "$f" "$STAGE/live/pstore-live/" 2>/dev/null
  done
fi

# v3.1: live Magisk snapshot — current state at moment of collection
mkdir -p "$STAGE/live/magisk-now"
{
  echo "=== magisk -V / -v ==="
  magisk -V 2>&1
  magisk -v 2>&1
  echo ""
  echo "=== installed modules ==="
  for d in /data/adb/modules/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    flags=""
    [ -f "$d/disable" ]    && flags="${flags}DISABLED "
    [ -f "$d/remove" ]     && flags="${flags}PENDING_REMOVE "
    [ -f "$d/update" ]     && flags="${flags}UPDATED "
    [ -f "$d/skip_mount" ] && flags="${flags}SKIP_MOUNT "
    ver="?"
    [ -f "$d/module.prop" ] && ver=$(grep "^version=" "$d/module.prop" | cut -d= -f2)
    echo "  $name $ver $flags"
  done
  echo ""
  echo "=== denylist ==="
  magisk --denylist ls 2>&1 | head
  echo ""
  echo "=== zygisk status ==="
  magisk --zygisk 2>&1 | head -2
} > "$STAGE/live/magisk-now/state.txt" 2>&1
[ -f /cache/magisk.log ]    && tail -300 /cache/magisk.log    > "$STAGE/live/magisk-now/cache-magisk.log" 2>/dev/null
[ -f /data/adb/magisk.log ] && tail -300 /data/adb/magisk.log > "$STAGE/live/magisk-now/data-magisk.log" 2>/dev/null

# v3.1: SELinux denials snapshot (persists what nh-logcatd watcher captured)
[ -f /data/local/log/selinux-denials.log ] && \
  cp /data/local/log/selinux-denials.log "$STAGE/live/" 2>/dev/null
# Also fresh dmesg-derived denials at moment of collection
dmesg 2>&1 | grep -E "type=1400|avc:[[:space:]]+denied" | tail -200 > "$STAGE/live/selinux-denials-fresh.log" 2>/dev/null

# v3: kernel runtime state — useful for diagnosing wifi/sensor weirdness
{
  echo "=== /proc/cmdline ==="
  cat /proc/cmdline 2>/dev/null
  echo ""
  echo "=== printk levels (current,default,min,boot) ==="
  cat /proc/sys/kernel/printk 2>/dev/null
  echo ""
  echo "=== ramoops cmdline (verifies kernel built with v1.1.1 features) ==="
  grep -oE "ramoops\.[a-z_]+=[0-9]+" /proc/cmdline 2>/dev/null
  echo ""
  echo "=== /proc/version ==="
  cat /proc/version 2>/dev/null
  echo ""
  echo "=== /sys/module/wlan/parameters ==="
  for p in con_mode con_mode_ftm fwpath country_code timer_multiplier qdf_log_dump_at_kernel_enable; do
    val=$(cat "/sys/module/wlan/parameters/$p" 2>/dev/null)
    echo "  $p = $val"
  done
  echo ""
  echo "=== ip link (network interfaces) ==="
  ip link show 2>/dev/null
  echo ""
  echo "=== /proc/interrupts (top 30 by line — check IRQ pressure) ==="
  cat /proc/interrupts 2>/dev/null | head -30
  echo ""
  echo "=== /proc/meminfo (top) ==="
  head -10 /proc/meminfo 2>/dev/null
  echo ""
  echo "=== uptime + load ==="
  uptime 2>/dev/null
} > "$STAGE/live/kernel-runtime-state.txt" 2>&1

# Pack
cd /data/local/tmp
tar czf "$OUT" -C nh-logs-stage . 2>/dev/null

if [ -s "$OUT" ]; then
  echo "[+] Bundled $(du -h "$OUT" | cut -f1) → $OUT"
  echo "[+] To retrieve from PC:  adb pull $OUT"
  # Highlight if there are persisted incidents (panic snapshots that don't rotate)
  INC_COUNT=$(ls -d "$LOGDIR/incidents/"*/ 2>/dev/null | wc -l)
  if [ "$INC_COUNT" -gt 0 ]; then
    echo
    echo "  ⚠ ${INC_COUNT} panic incident(s) frozen in /data/local/log/incidents/ —"
    echo "    these are preserved across all rotations. Inspect after pull:"
    ls -1d "$LOGDIR/incidents/"*/ 2>/dev/null | head -5 | while read inc; do
      reason=""
      [ -f "${inc}REASON.txt" ] && reason="$(cat "${inc}REASON.txt")"
      echo "      $(basename "${inc%/}")  ${reason}"
    done
  fi
else
  echo "[!] Tarball is empty — check that /data/local/log/ has content"
fi

rm -rf "$STAGE"
