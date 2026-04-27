#!/bin/bash
# Apply source patches:
# 1. Pull Focaltech firmware blob missing from kernel source
# 2. Fix hh_msgq.h stub functions returning wrong type (5 sed)
# 3. Add missing #include <linux/compat.h> in msm_cvp_ioctl.c (1 sed)
# 4. Apply Realtek out-of-tree driver patches (CFI fix + ARM64 platform + MODULE_IMPORT_NS)
#
# Note: Kali QCACLD-3.0 frame injection is already integrated into our kernel fork
# (8 commits on branch nethunter-23.2 — see https://github.com/ilyamen/android_kernel_nothing_sm7325_nethunter).
# This script no longer applies it via `git am`.
set -e
export MSYS_NO_PATHCONV=1

CONTAINER=spacewar-build
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Push our realtek-patches/ into the container — drivers are patched there
docker cp "$REPO_ROOT/realtek-patches/" $CONTAINER:/work/realtek-patches/

docker exec -i $CONTAINER bash <<'EOF'
set -e
export MSYS_NO_PATHCONV=1

# 0. Focaltech touchscreen firmware blob (FT3680_WXN_M146_V27_D01_20220706_app.i) — 598 KB header
#    Required by drivers/input/touchscreen/focaltech_touch/focaltech_flash.c at compile time.
#    Missing from upstream lineage source. Pull from kimocoder/android_kernel_msm-5.4_nothing_sm7325.
FW_DIR=/work/kernel-los/drivers/input/touchscreen/focaltech_touch/include/firmware
FW_FILE=$FW_DIR/FT3680_WXN_M146_V27_D01_20220706_app.i
if [ ! -s "$FW_FILE" ]; then
  mkdir -p "$FW_DIR"
  curl -sLf "https://raw.githubusercontent.com/kimocoder/android_kernel_msm-5.4_nothing_sm7325/nethunter-15.0/drivers/input/touchscreen/focaltech_touch/include/firmware/FT3680_WXN_M146_V27_D01_20220706_app.i" \
    -o "$FW_FILE"
  echo "[+] Pulled missing Focaltech firmware blob ($(wc -c < "$FW_FILE") bytes)"
fi
# fw_sample.i is a secondary firmware placeholder — upstream is 0 bytes — touch.
touch "$FW_DIR/fw_sample.i"

# 1. haven/hh_msgq.h — five stub functions return wrong type (int returning void* via ERR_PTR)
H=/work/kernel-los/include/linux/haven/hh_msgq.h
sed -i "/static inline int hh_msgq_unregister/,/^}$/ s/return ERR_PTR(-ENODEV);/return -ENODEV;/" $H
sed -i "/static inline int hh_msgq_send/,/^}$/ s/return ERR_PTR(-EINVAL);/return -EINVAL;/" $H
sed -i "/static inline int hh_msgq_recv/,/^}$/ s/return ERR_PTR(-EINVAL);/return -EINVAL;/" $H
sed -i "/static inline int hh_msgq_populate_cap_info/,/^}$/ s/return ERR_PTR(-EINVAL);/return -EINVAL;/" $H
sed -i "/static inline int hh_msgq_probe/,/^}$/ s/return ERR_PTR(-ENODEV);/return -ENODEV;/" $H
echo "[+] Patched hh_msgq.h"

# 2. msm_cvp_ioctl.c — missing <linux/compat.h> for compat_ptr()
F=/work/kernel-los/drivers/media/platform/msm/cvp/msm_cvp_ioctl.c
grep -q "include <linux/compat.h>" $F || sed -i "6i #include <linux/compat.h>" $F
echo "[+] Patched msm_cvp_ioctl.c"

# 3. Realtek out-of-tree driver patches (CFI signature fix + ARM64 platform + MODULE_IMPORT_NS).
#    See realtek-patches/README.md for what each patch contains.
echo "[*] Applying Realtek driver patches"
for entry in \
    "rtl8188eus:rtl8188eus-cfi-fix.patch" \
    "88x2bu-20210702:88x2bu-20210702-cfi-fix.patch" \
    "8821cu-20210916:8821cu-20210916-cfi-fix.patch"; do
  drv="${entry%%:*}"
  patch="${entry##*:}"
  cd "/work/$drv"
  # Idempotent — if patch already applied (e.g. re-run), skip silently
  if git apply --check --reverse "/work/realtek-patches/$patch" 2>/dev/null; then
    echo "[~] $drv: patch already applied (skipping)"
  else
    git apply "/work/realtek-patches/$patch"
    echo "[+] $drv: patch applied"
  fi
  cd /work
done

echo "[+] All patches applied."
EOF
