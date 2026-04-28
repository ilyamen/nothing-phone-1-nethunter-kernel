#!/system/bin/sh
# nh-overlay-base — first-run F-Droid repo auto-add via fdroidrepos:// intents.
#
# F-Droid 1.23.2 has a fragile `additional_repos.xml` mechanism (deprecated)
# AND its DB schema changes between versions, so SQL injection is brittle.
#
# Cleanest path: fire fdroidrepos:// intents that F-Droid already handles
# natively. Note `fdroidrepos://` (with S) — fdroidrepo:// without S maps to
# HTTP and fails on https-only repos with "Unhandled redirect" 301.
#
# Fired ONCE per device: marker file /data/adb/.nh-overlay-base.repos-added
# prevents re-firing on every boot.

MODDIR=${0%/*}
MARKER=/data/adb/.nh-overlay-base.repos-added
LOG=/data/local/log/nh-overlay-base.log
mkdir -p /data/local/log 2>/dev/null

{
  echo "=== $(date) nh-overlay-base service.sh ==="

  # Already done?
  if [ -f "$MARKER" ]; then
    echo "[=] repos already added (marker present), skipping"
    exit 0
  fi

  # Wait for boot_completed AND user PIN-unlock (FBE)
  i=0
  until [ "$(getprop sys.boot_completed)" = "1" ] || [ $i -gt 60 ]; do
    sleep 2; i=$((i+1))
  done

  # Wait for /data/data/* to become accessible (FBE unlock)
  i=0
  until [ -d /data/data/org.fdroid.fdroid/files ] || [ $i -gt 30 ]; do
    sleep 5; i=$((i+1))
  done

  # Extra cushion — let F-Droid finish first-launch DB init
  sleep 15

  echo "[*] firing fdroidrepos:// intent for NetHunter Store"
  am start -a android.intent.action.VIEW \
    -d "fdroidrepos://store.nethunter.com/repo?fingerprint=FE7A23DFC003A1CF2D2ADD2469B9C0C49B206BA5DC9EDD6563B3B7EB6A8F5FAB" \
    2>&1 | tail -2
  sleep 3

  echo "[*] firing fdroidrepos:// intent for IzzyOnDroid"
  am start -a android.intent.action.VIEW \
    -d "fdroidrepos://apt.izzysoft.de/fdroid/repo?fingerprint=3BF0D6ABFEAE2F401707B6D966BE743BF0EEE49C2561B9BA39073711F628937A" \
    2>&1 | tail -2

  # Mark done so we don't re-fire on every boot
  touch "$MARKER" 2>/dev/null

  echo "[+] done. User must tap 'Add' on the F-Droid prompts (one-time)."
} >> "$LOG" 2>&1
