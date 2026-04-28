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
