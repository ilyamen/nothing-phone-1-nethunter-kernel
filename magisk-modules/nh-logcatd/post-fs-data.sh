#!/system/bin/sh
# nh-logcatd v2 — early-boot grab of pstore + auto-freeze panic incidents.
# Runs at post-fs-data Magisk hook (before service.d).

LOGDIR=/data/local/log
mkdir -p "$LOGDIR/pstore" "$LOGDIR/boot-history" "$LOGDIR/nh-modules" "$LOGDIR/incidents" 2>/dev/null
chmod 755 "$LOGDIR" "$LOGDIR/pstore" "$LOGDIR/boot-history" "$LOGDIR/nh-modules" "$LOGDIR/incidents" 2>/dev/null

STAMP=$(date +%Y%m%d-%H%M%S)
PSTORE_HAD_DATA=0

# === Layer D: grab /sys/fs/pstore (panic data from previous boot) ===
if [ -d /sys/fs/pstore ]; then
  for f in /sys/fs/pstore/*; do
    [ -e "$f" ] || continue
    name=$(basename "$f")
    cp "$f" "$LOGDIR/pstore/${STAMP}_${name}" 2>/dev/null
    rm "$f" 2>/dev/null
    PSTORE_HAD_DATA=1
  done
fi

# === Also try /proc/last_kmsg ===
if [ -s /proc/last_kmsg ]; then
  cp /proc/last_kmsg "$LOGDIR/pstore/${STAMP}_last_kmsg.log" 2>/dev/null
  PSTORE_HAD_DATA=1
fi

# === Layer E: boot dmesg snapshot ===
dmesg > "$LOGDIR/boot-history/dmesg-${STAMP}.log" 2>/dev/null
chmod 644 "$LOGDIR/boot-history/dmesg-${STAMP}.log" 2>/dev/null

# === NEW Layer H: auto-freeze incident if pstore had panic data ===
# Triggers once per panic→reboot cycle. Captures everything into a non-rotating
# folder so the problem snapshot survives any number of normal-day rotations
# until user manually deletes it.
if [ "$PSTORE_HAD_DATA" = "1" ]; then
  INC="$LOGDIR/incidents/panic-${STAMP}"
  mkdir -p "$INC"
  echo "Incident: kernel panic detected via pstore at boot ${STAMP}" > "$INC/REASON.txt"
  date > "$INC/captured_at.txt"
  uname -a > "$INC/uname.txt"
  cat /proc/cmdline > "$INC/cmdline.txt"
  ls /data/adb/modules > "$INC/magisk-modules.txt"
  # Snapshot ALL current log files at moment of post-fs-data
  cp "$LOGDIR/pstore/${STAMP}_"* "$INC/" 2>/dev/null
  cp "$LOGDIR/logcat.log"* "$INC/" 2>/dev/null
  cp "$LOGDIR/dmesg-"*.log "$INC/" 2>/dev/null
  cp -r "$LOGDIR/boot-history/" "$INC/boot-history/" 2>/dev/null
  cp "$LOGDIR/boot-history/dmesg-${STAMP}.log" "$INC/current-boot-dmesg.log" 2>/dev/null
fi

# === Rotation rules ===
# boot-history: keep 50
ls -t "$LOGDIR/boot-history/" 2>/dev/null | tail -n +51 | while read old; do
  rm -f "$LOGDIR/boot-history/$old" 2>/dev/null
done
# incidents: keep 5 (panic events are rare; this is plenty of history)
ls -dt "$LOGDIR/incidents/"*/ 2>/dev/null | tail -n +6 | while read old; do
  rm -rf "$old" 2>/dev/null
done

# === Layer F: copy other Magisk modules' /cache logs to persistent /data ===
for f in /cache/nh-*.log /cache/realtek-*.log; do
  [ -e "$f" ] || continue
  base=$(basename "$f")
  cp "$f" "$LOGDIR/nh-modules/${base%.log}-${STAMP}.log" 2>/dev/null
done
# Rotate nh-modules: keep 100 most recent files
ls -t "$LOGDIR/nh-modules/" 2>/dev/null | tail -n +101 | while read old; do
  rm -f "$LOGDIR/nh-modules/$old" 2>/dev/null
done

# === Storage budget enforcement: if /data/local/log/ > 400 MB → trim ===
# Use du -sm (size in MB). Aggressive trim only kicks in if budget exceeded.
SIZE_MB=$(du -sm "$LOGDIR" 2>/dev/null | cut -f1)
if [ -n "$SIZE_MB" ] && [ "$SIZE_MB" -gt 400 ]; then
  # Step 1: trim boot-history to 20 (was 50)
  ls -t "$LOGDIR/boot-history/" 2>/dev/null | tail -n +21 | while read old; do
    rm -f "$LOGDIR/boot-history/$old" 2>/dev/null
  done
  # Step 2: if still > 400 MB, trim incidents to 3 (was 5)
  SIZE_MB=$(du -sm "$LOGDIR" 2>/dev/null | cut -f1)
  if [ "$SIZE_MB" -gt 400 ]; then
    ls -dt "$LOGDIR/incidents/"*/ 2>/dev/null | tail -n +4 | while read old; do
      rm -rf "$old" 2>/dev/null
    done
  fi
fi
