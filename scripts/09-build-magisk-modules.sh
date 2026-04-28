#!/bin/bash
# Pack each magisk-modules/<module>/ source tree into a flashable .zip.
# Outputs land in magisk-modules/build/.
# Uses docker container's `zip` tool — local Git Bash usually lacks it,
# and PowerShell's Compress-Archive uses backslash paths that break
# Magisk's installer (we hit this bug earlier in the project).
set -e
export MSYS_NO_PATHCONV=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$REPO_ROOT/magisk-modules"
BUILD_DIR="$SRC_DIR/build"

mkdir -p "$BUILD_DIR"
rm -f "$BUILD_DIR"/*.zip

CONTAINER=spacewar-build

# Ensure zip is available in the container
docker exec "$CONTAINER" bash -c 'command -v zip >/dev/null || (apt-get update -qq && apt-get install -y zip >/dev/null)'

for module_dir in "$SRC_DIR"/*/; do
  module=$(basename "$module_dir")
  # Skip build/ output dir and external/ third-party staging
  case "$module" in
    build|external) continue ;;
  esac
  # Skip if not a real module (no module.prop)
  [ -f "$module_dir/module.prop" ] || { echo "[skip] $module — no module.prop"; continue; }

  out_zip="$BUILD_DIR/$module.zip"
  echo "[*] packing $module → $(basename "$out_zip")"

  tar c -C "$module_dir" --owner=0 --group=0 . | \
    docker exec -i "$CONTAINER" bash -c '
      rm -rf /tmp/zipsrc /tmp/out.zip
      mkdir /tmp/zipsrc && cd /tmp/zipsrc && tar x
      # Always-executable scripts
      [ -f post-fs-data.sh ]   && chmod 755 post-fs-data.sh
      [ -f service.sh ]        && chmod 755 service.sh
      [ -f customize.sh ]      && chmod 755 customize.sh
      [ -d system/bin ]        && chmod 755 system/bin/*.sh 2>/dev/null
      [ -d system/addon.d ]    && chmod 755 system/addon.d/*.sh 2>/dev/null
      [ -d META-INF/com/google/android ] && chmod 755 META-INF/com/google/android/update-binary 2>/dev/null
      zip -qr9 /tmp/out.zip .
      cat /tmp/out.zip
    ' > "$out_zip"

  size=$(stat -c%s "$out_zip" 2>/dev/null || wc -c < "$out_zip")
  echo "    [+] $size bytes"
done

echo
echo "[+] Built $(ls "$BUILD_DIR"/*.zip 2>/dev/null | wc -l) module zips in $BUILD_DIR"
ls -lh "$BUILD_DIR"/*.zip 2>/dev/null
