#!/system/bin/sh
# nh-logcatd v3 — early-boot grab of pstore + auto-freeze panic incidents.
# v1.1.1 kernel exposes more pstore types (dmesg/console/ftrace/pmsg),
# all 4 caught by the pstore wildcard below.
# Runs at post-fs-data Magisk hook (before service.d).

LOGDIR=/data/local/log
mkdir -p "$LOGDIR/pstore" "$LOGDIR/boot-history" "$LOGDIR/nh-modules" "$LOGDIR/incidents" \
         "$LOGDIR/magisk-snapshots" 2>/dev/null
chmod 755 "$LOGDIR" "$LOGDIR/pstore" "$LOGDIR/boot-history" "$LOGDIR/nh-modules" \
          "$LOGDIR/incidents" "$LOGDIR/magisk-snapshots" 2>/dev/null

STAMP=$(date +%Y%m%d-%H%M%S)
PSTORE_HAD_DATA=0
PSTORE_TYPES=""

# === Layer D: grab /sys/fs/pstore (panic + boot data from previous boot) ===
# v1.1.1 ramoops region is 4MB (was 1MB), with 4 separate sub-rings:
#   • dmesg-ramoops-0     (oops + panic — up to 2MB)
#   • console-ramoops-0   (boot console history — up to 512KB)
#   • ftrace-ramoops-0    (last 1MB of function trace — if FTRACE active)
#   • pmsg-ramoops-0      (userspace pmsg ring — boot markers, up to 512KB)
# Wildcard below captures all of them.
if [ -d /sys/fs/pstore ]; then
  for f in /sys/fs/pstore/*; do
    [ -e "$f" ] || continue
    name=$(basename "$f")
    cp "$f" "$LOGDIR/pstore/${STAMP}_${name}" 2>/dev/null
    rm "$f" 2>/dev/null
    PSTORE_HAD_DATA=1
    # Track which types we saw — useful for incident triage
    case "$name" in
      dmesg-*)   PSTORE_TYPES="${PSTORE_TYPES}dmesg " ;;
      console-*) PSTORE_TYPES="${PSTORE_TYPES}console " ;;
      ftrace-*)  PSTORE_TYPES="${PSTORE_TYPES}ftrace " ;;
      pmsg-*)    PSTORE_TYPES="${PSTORE_TYPES}pmsg " ;;
    esac
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

# === Layer H: auto-freeze incident if pstore had panic data ===
# Triggers once per panic→reboot cycle. Captures everything into a non-rotating
# folder so the problem snapshot survives any number of normal-day rotations
# until user manually deletes it.
#
# v3: distinguish panic vs clean-shutdown. Pstore data with ONLY pmsg-ramoops
# is normal (every boot writes a marker via /dev/pmsg0). Pstore data with
# dmesg-ramoops or console-ramoops indicates an actual kernel oops/panic.
if [ "$PSTORE_HAD_DATA" = "1" ]; then
  # v3.2 fix: ONLY dmesg-ramoops indicates a real panic/oops.
  # console-ramoops is written every boot (boot console history), not just on
  # panic. ftrace-ramoops likewise written every boot if FTRACE is active.
  # pmsg-ramoops is our own boot marker. v3.0 incident filter mis-classified
  # all 4 boot-history captures as "panic" — verified empirically by 4 false
  # positives over a single day's iter testing.
  case "$PSTORE_TYPES" in
    *dmesg*)
      INC="$LOGDIR/incidents/panic-${STAMP}"
      mkdir -p "$INC"
      echo "Incident: kernel panic/oops detected via pstore at boot ${STAMP}" > "$INC/REASON.txt"
      echo "Pstore types captured: ${PSTORE_TYPES}" >> "$INC/REASON.txt"
      date > "$INC/captured_at.txt"
      uname -a > "$INC/uname.txt"
      cat /proc/cmdline > "$INC/cmdline.txt"
      cat /proc/version > "$INC/version.txt"
      ls /data/adb/modules > "$INC/magisk-modules.txt"
      # Snapshot ALL current log files at moment of post-fs-data
      cp "$LOGDIR/pstore/${STAMP}_"* "$INC/" 2>/dev/null
      cp "$LOGDIR/logcat.log"* "$INC/" 2>/dev/null
      cp "$LOGDIR/dmesg-"*.log "$INC/" 2>/dev/null
      cp -r "$LOGDIR/boot-history/" "$INC/boot-history/" 2>/dev/null
      cp "$LOGDIR/boot-history/dmesg-${STAMP}.log" "$INC/current-boot-dmesg.log" 2>/dev/null
      ;;
  esac
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

# === Layer J (v3.1): Magisk ecosystem snapshot ===
# Captures the state of EVERY Magisk module at this boot — versions, disable/
# remove/update flags, mount-skip flags, post-fs and service script presence.
# This is critical for diagnosing "why isn't <module> working" weeks after the
# fact: looking back at the snapshot from when the issue started lets you see
# which modules were installed, disabled, or partially-broken at that boot.
# Also captures Magisk daemon's own log so we can see SELinux issues, mount
# failures, and policy violations that Magisk itself observed.
SNAP="$LOGDIR/magisk-snapshots/${STAMP}"
mkdir -p "$SNAP"
{
  echo "=== Magisk version ==="
  magisk -V 2>&1
  magisk -v 2>&1
  echo ""
  echo "=== /data/adb/modules listing ==="
  ls -la /data/adb/modules/ 2>&1
  echo ""
  echo "=== Per-module state ==="
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
    code="?"
    [ -f "$d/module.prop" ] && code=$(grep "^versionCode=" "$d/module.prop" | cut -d= -f2)
    has_post="-"
    [ -f "$d/post-fs-data.sh" ] && has_post="post-fs"
    has_svc="-"
    [ -f "$d/service.sh" ] && has_svc="service"
    has_late="-"
    [ -f "$d/boot-completed.sh" ] && has_late="boot-completed"
    echo "  $name | ver=$ver code=$code | $has_post $has_svc $has_late | $flags"
  done
  echo ""
  echo "=== /data/adb/post-fs-data.d/ ==="
  ls -la /data/adb/post-fs-data.d/ 2>&1
  echo ""
  echo "=== /data/adb/service.d/ ==="
  ls -la /data/adb/service.d/ 2>&1
  echo ""
  echo "=== Magisk denylist ==="
  magisk --denylist ls 2>&1 | head -30
  echo ""
  echo "=== /cache/magisk.log (last 100 lines) ==="
  tail -100 /cache/magisk.log 2>&1
  echo ""
  echo "=== /data/adb/magisk.log (last 100 lines) ==="
  tail -100 /data/adb/magisk.log 2>&1
} > "$SNAP/magisk-state.txt" 2>&1

# Also capture full magisk log files (raw, unfiltered)
[ -f /cache/magisk.log ]      && cp /cache/magisk.log "$SNAP/cache-magisk.log" 2>/dev/null
[ -f /data/adb/magisk.log ]   && cp /data/adb/magisk.log "$SNAP/data-adb-magisk.log" 2>/dev/null

# Rotate magisk-snapshots: keep last 30 boots
ls -dt "$LOGDIR/magisk-snapshots/"*/ 2>/dev/null | tail -n +31 | while read old; do
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

# === Storage budget enforcement: if /data/local/log/ > 600 MB → trim ===
# v3: budget raised from 400MB to 600MB (logcat ring 64MB → 128MB pool).
# Use du -sm (size in MB). Aggressive trim only kicks in if budget exceeded.
SIZE_MB=$(du -sm "$LOGDIR" 2>/dev/null | cut -f1)
if [ -n "$SIZE_MB" ] && [ "$SIZE_MB" -gt 600 ]; then
  # Step 1: trim boot-history to 20 (was 50)
  ls -t "$LOGDIR/boot-history/" 2>/dev/null | tail -n +21 | while read old; do
    rm -f "$LOGDIR/boot-history/$old" 2>/dev/null
  done
  # Step 2: if still > 600 MB, trim incidents to 3 (was 5)
  SIZE_MB=$(du -sm "$LOGDIR" 2>/dev/null | cut -f1)
  if [ "$SIZE_MB" -gt 600 ]; then
    ls -dt "$LOGDIR/incidents/"*/ 2>/dev/null | tail -n +4 | while read old; do
      rm -rf "$old" 2>/dev/null
    done
  fi
  # Step 3: if STILL >600MB, trim pstore archive to last 30 entries
  SIZE_MB=$(du -sm "$LOGDIR" 2>/dev/null | cut -f1)
  if [ "$SIZE_MB" -gt 600 ]; then
    ls -t "$LOGDIR/pstore/" 2>/dev/null | tail -n +31 | while read old; do
      rm -f "$LOGDIR/pstore/$old" 2>/dev/null
    done
  fi
fi
