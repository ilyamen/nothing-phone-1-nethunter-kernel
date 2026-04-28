#!/bin/bash
# Manual local release: assembles all artifacts → release-staging/<VERSION>/ →
# uploads to GitHub Releases via `gh release create`.
#
# Prerequisites:
#   - Build pipeline already ran: scripts/01-08 produced output/Image, AnyKernel
#     zip, boot.img.
#   - scripts/09-build-magisk-modules.sh produced magisk-modules/build/*.zip
#   - GitHub CLI authenticated:  gh auth status
#   - Working tree clean and on a tag matching $VERSION
#
# Usage:  scripts/10-make-release.sh v1.0.0
#         scripts/10-make-release.sh v1.0.0 --draft       # don't publish, just stage
#         scripts/10-make-release.sh v1.0.0 --no-upload   # only stage locally
set -e
export MSYS_NO_PATHCONV=1

VERSION="${1:?Usage: $0 vX.Y.Z [--draft|--no-upload]}"
MODE="${2:-publish}"   # publish | --draft | --no-upload

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

set -a; . kernel-pin.env; set +a

REL_DIR="release-staging/$VERSION"
mkdir -p "$REL_DIR"
rm -f "$REL_DIR"/*

echo "[*] === Release $VERSION ==="
echo "[*] Kernel SHA: $KERNEL_SHA"
echo "[*] Toolchain:  $TOOLCHAIN_VERSION"
echo

# 1. Verify pipeline outputs exist
LATEST_BOOT=$(ls -t output/nethunter-*-boot_a.img 2>/dev/null | head -1)
if [ -z "$LATEST_BOOT" ]; then
  echo "[!] No boot.img in output/. Run scripts/05 + scripts/08 first."
  exit 1
fi
echo "[+] boot.img:  $LATEST_BOOT"

ANYKERNEL_ZIP=output/spacewar-nethunter-FINAL.zip
if [ ! -f "$ANYKERNEL_ZIP" ]; then
  echo "[!] AnyKernel3 zip missing. Run scripts/07-package-zip.sh first."
  exit 1
fi
echo "[+] AnyKernel3: $ANYKERNEL_ZIP"

MODULE_DIR=magisk-modules/build
if ! ls "$MODULE_DIR"/*.zip >/dev/null 2>&1; then
  echo "[!] No Magisk module zips. Run scripts/09-build-magisk-modules.sh first."
  exit 1
fi
NUM_MODULES=$(ls "$MODULE_DIR"/*.zip | wc -l)
echo "[+] Magisk modules: $NUM_MODULES"
echo

# 2. Stage artifacts with versioned names
echo "[*] Staging artifacts to $REL_DIR/"
cp "$LATEST_BOOT"    "$REL_DIR/spacewar-nethunter-kernel-${VERSION}-boot.img"
cp "$ANYKERNEL_ZIP"  "$REL_DIR/spacewar-nethunter-kernel-${VERSION}-AnyKernel3.zip"

# Bundle of all magisk modules
tar czf "$REL_DIR/spacewar-nethunter-modules-${VERSION}.tar.gz" -C "$MODULE_DIR" .
# Plus individual modules for users who want à-la-carte
for z in "$MODULE_DIR"/*.zip; do
  cp "$z" "$REL_DIR/$(basename "$z" .zip)-${VERSION}.zip"
done

# Documentation
[ -f docs/INSTALL.md ] && cp docs/INSTALL.md  "$REL_DIR/INSTALL.md"
[ -f CHANGELOG.md ]    && cp CHANGELOG.md     "$REL_DIR/CHANGELOG.md"

# Checksums (deterministic across runs)
( cd "$REL_DIR" && sha256sum * > checksums.txt )

echo
echo "[+] Release manifest:"
ls -lh "$REL_DIR"/

# 3. Publish to GitHub
case "$MODE" in
  --no-upload)
    echo
    echo "[*] --no-upload — staged only, not pushing to GitHub."
    exit 0
    ;;
  --draft)  GH_FLAGS=("--draft") ;;
  *)        GH_FLAGS=() ;;
esac

if ! command -v gh >/dev/null; then
  echo "[!] gh CLI not installed. Install from https://cli.github.com/ or upload $REL_DIR/* manually."
  exit 1
fi

NOTES_FILE="release-notes/${VERSION}.md"
if [ ! -f "$NOTES_FILE" ]; then
  echo "[!] release-notes/${VERSION}.md not found — using auto-generated."
  NOTES_FLAG=("--generate-notes")
else
  NOTES_FLAG=("--notes-file" "$NOTES_FILE")
fi

# Tag must exist
if ! git rev-parse "$VERSION" >/dev/null 2>&1; then
  echo "[!] Tag $VERSION doesn't exist. Create with: git tag -a $VERSION -m 'Release $VERSION'"
  exit 1
fi

echo
echo "[*] Creating GitHub release..."
gh release create "$VERSION" \
  --title "NetHunter Kernel ${VERSION} — Nothing Phone 1 (spacewar)" \
  "${NOTES_FLAG[@]}" \
  "${GH_FLAGS[@]}" \
  "$REL_DIR"/*

echo
echo "[+] Release published:"
gh release view "$VERSION" --web 2>/dev/null || gh release view "$VERSION"
