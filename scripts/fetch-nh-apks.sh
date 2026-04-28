#!/bin/bash
# Populate magisk-modules/nh-overlay-base/system/priv-app/ with the 5 APKs
# the overlay deploys to /system/priv-app/.
#
# Sources (in priority order):
#   1. installers/*.apk in this repo (cached copies of NetHunter app + Store)
#   2. adb pull from a connected phone where you previously installed via Store
#   3. f-droid.org direct download (for F-Droid client + Privileged Extension)
#
# The Kali NetHunter gitlab releases are stale (last published 2019 — they now
# distribute via NetHunter Store at store.nethunter.com/repo). To get the latest
# Terminal/KeX, install them on a phone via NetHunter Store first, then this
# script pulls them via `adb pull $(pm path <pkg>)`.
#
# Usage:  scripts/fetch-nh-apks.sh
#         scripts/fetch-nh-apks.sh --force      # re-fetch even if exists
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PRIV_APP="$REPO_ROOT/magisk-modules/nh-overlay-base/system/priv-app"
INSTALLERS="$REPO_ROOT/installers"

FORCE="${1:-}"

place() {
  local dir="$1" name="$2" src="$3"
  local target="$PRIV_APP/$dir/$name"
  mkdir -p "$PRIV_APP/$dir"
  if [ -f "$target" ] && [ "$FORCE" != "--force" ]; then
    echo "[=] $dir/$name (exists, skipping; --force to overwrite)"
    return 0
  fi
  if [ ! -f "$src" ]; then
    echo "[!] source not found: $src"
    return 1
  fi
  cp "$src" "$target"
  local size=$(stat -c%s "$target" 2>/dev/null || wc -c <"$target")
  echo "[+] $dir/$name ← $src (${size} bytes)"
}

fetch_url() {
  local dir="$1" name="$2" url="$3"
  local target="$PRIV_APP/$dir/$name"
  mkdir -p "$PRIV_APP/$dir"
  if [ -f "$target" ] && [ "$FORCE" != "--force" ]; then
    echo "[=] $dir/$name (exists, skipping; --force to overwrite)"
    return 0
  fi
  echo "[*] $dir/$name ← $url"
  if curl -fsSL --output "$target" "$url"; then
    local size=$(stat -c%s "$target" 2>/dev/null || wc -c <"$target")
    echo "    [+] ${size} bytes"
  else
    echo "    [!] FAILED"
    rm -f "$target"
    return 1
  fi
}

adb_pull_apk() {
  local dir="$1" name="$2" pkg="$3"
  local target="$PRIV_APP/$dir/$name"
  mkdir -p "$PRIV_APP/$dir"
  if [ -f "$target" ] && [ "$FORCE" != "--force" ]; then
    echo "[=] $dir/$name (exists, skipping; --force to overwrite)"
    return 0
  fi
  echo "[*] $dir/$name ← adb pull (pkg=$pkg)"
  if ! command -v adb >/dev/null; then
    echo "    [!] adb not in PATH — install Android Platform Tools"
    return 1
  fi
  # Multi-device aware: prefer ANDROID_SERIAL env var, else first listed device.
  local adb_args=""
  if [ -n "$ANDROID_SERIAL" ]; then
    adb_args="-s $ANDROID_SERIAL"
  else
    local count
    count=$(adb devices 2>/dev/null | grep -cE "^\S+\s+device$")
    if [ "$count" -gt 1 ]; then
      local first
      first=$(adb devices 2>/dev/null | grep -E "^\S+\s+device$" | head -1 | awk '{print $1}')
      echo "    [i] Multiple ADB devices found, using first: $first"
      adb_args="-s $first"
    fi
  fi
  local apk_path
  apk_path=$(adb $adb_args shell "pm path $pkg" 2>/dev/null | sed 's/^package://' | tr -d '\r' | head -1) || true
  if [ -z "$apk_path" ]; then
    echo "    [!] $pkg not installed on phone — install via NetHunter Store first"
    return 1
  fi
  # adb on Windows doesn't understand /c/Users/... Git Bash paths.
  # Pull to current dir (CWD-relative) as a stub name, then mv to target.
  local tmpname="_nhfetch_$(date +%s)_$$.apk"
  ( cd "$REPO_ROOT" && adb $adb_args pull "$apk_path" "$tmpname" 2>&1 | tail -1 )
  if [ -f "$REPO_ROOT/$tmpname" ]; then
    mv "$REPO_ROOT/$tmpname" "$target"
    local size=$(stat -c%s "$target" 2>/dev/null || wc -c <"$target")
    echo "    [+] ${size} bytes"
  else
    echo "    [!] adb pull FAILED — phone may have lost connection"
    return 1
  fi
}

# === 1. NetHunter app — from installers/ cache ===
if [ -f "$INSTALLERS/NetHunter-2026.1.apk" ]; then
  place NetHunter NetHunter.apk "$INSTALLERS/NetHunter-2026.1.apk"
else
  echo "[!] $INSTALLERS/NetHunter-2026.1.apk missing"
  echo "    Download from https://store.nethunter.com or pull via adb if installed."
fi

# === 2. NetHunter Terminal — adb pull from phone ===
adb_pull_apk NetHunterTerminal NetHunterTerminal.apk com.offsec.nhterm \
  || echo "    [hint] Install NetHunter Terminal via NetHunter Store on phone first"

# === 3. NetHunter KeX — adb pull from phone (optional) ===
adb_pull_apk NetHunterKeX NetHunterKeX.apk com.offsec.nethunter.kex \
  || echo "    [hint] (optional) Install NetHunter KeX via Store if you want VNC GUI"

# === 4. F-Droid client (replaces NetHunter Store as canonical apk source) ===
fetch_url FDroid FDroid.apk "https://f-droid.org/F-Droid.apk"

# === 5. F-Droid Privileged Extension ===
fetch_url FDroidPrivilegedExtension FDroidPrivilegedExtension.apk \
  "https://f-droid.org/repo/org.fdroid.fdroid.privileged_2130.apk"

echo
echo "[+] Final state:"
find "$PRIV_APP" -name '*.apk' -exec stat -c '  %n: %s bytes' {} \; 2>/dev/null
echo
TOTAL=$(du -sh "$PRIV_APP" 2>/dev/null | cut -f1)
echo "[+] /priv-app total: $TOTAL"
echo
echo "[*] Now run: scripts/09-build-magisk-modules.sh"
