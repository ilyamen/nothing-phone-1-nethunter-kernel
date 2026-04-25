#!/bin/bash
# Apply source patches:
# 1. hh_msgq.h — fix three int functions returning ERR_PTR (pointer)
# 2. msm_cvp_ioctl.c — add missing #include <linux/compat.h>
# 3. Realtek drivers — make MODULE_IMPORT_NS unconditional, drop Wno-stringop-overread,
#    drop -DRTW_ENABLE_WIFI_CONTROL_FUNC
set -e

CONTAINER=spacewar-build

docker exec $CONTAINER bash <<'EOF'
set -e

# 1. haven/hh_msgq.h — three stub functions return wrong type (int returning void* via ERR_PTR)
H=/work/kernel/include/linux/haven/hh_msgq.h
sed -i "/static inline int hh_msgq_unregister/,/^}$/ s/return ERR_PTR(-ENODEV);/return -ENODEV;/" $H
sed -i "/static inline int hh_msgq_send/,/^}$/ s/return ERR_PTR(-EINVAL);/return -EINVAL;/" $H
sed -i "/static inline int hh_msgq_recv/,/^}$/ s/return ERR_PTR(-EINVAL);/return -EINVAL;/" $H
sed -i "/static inline int hh_msgq_populate_cap_info/,/^}$/ s/return ERR_PTR(-EINVAL);/return -EINVAL;/" $H
sed -i "/static inline int hh_msgq_probe/,/^}$/ s/return ERR_PTR(-ENODEV);/return -ENODEV;/" $H
echo "[+] Patched hh_msgq.h"

# 2. msm_cvp_ioctl.c — missing <linux/compat.h> for compat_ptr()
F=/work/kernel/drivers/media/platform/msm/cvp/msm_cvp_ioctl.c
grep -q "include <linux/compat.h>" $F || sed -i "6i #include <linux/compat.h>" $F
echo "[+] Patched msm_cvp_ioctl.c"

# 3. Realtek drivers — Makefile fixes
for d in /work/rtl8188eus /work/88x2bu-20210702 /work/8821cu-20210916; do
  # Remove -Wno-stringop-overread (Clang doesn't recognize on older versions)
  sed -i 's/-Wno-stringop-overread//g' $d/Makefile
  # Remove -DRTW_ENABLE_WIFI_CONTROL_FUNC (forces inclusion of wlan_plat.h which we don't have)
  sed -i 's/-DRTW_ENABLE_WIFI_CONTROL_FUNC//g' $d/Makefile
  # Add ARM64 platform block to rtl8188eus (its Makefile doesn't have one)
  if [ "$d" = "/work/rtl8188eus" ] && ! grep -q "PLATFORM_ANDROID_ARM64.*y" $d/Makefile; then
    python3 - "$d/Makefile" <<'PY'
import sys
fn = sys.argv[1]
with open(fn) as f: lines = f.readlines()
in_block = False; insert_at = None; count = 0
for i, line in enumerate(lines):
    if "ifeq ($(CONFIG_PLATFORM_I386_PC), y)" in line:
        count += 1
        if count == 2: in_block = True
    elif in_block and line.strip() == "endif":
        insert_at = i + 1
        break
if insert_at:
    block = ("""
ifeq ($(CONFIG_PLATFORM_ANDROID_ARM64), y)
EXTRA_CFLAGS += -DCONFIG_LITTLE_ENDIAN
EXTRA_CFLAGS += -DCONFIG_IOCTL_CFG80211 -DRTW_USE_CFG80211_STA_EVENT
EXTRA_CFLAGS += -DCONFIG_PLATFORM_ANDROID -fno-pic
endif

""")
    lines.insert(insert_at, block)
    with open(fn, "w") as f: f.writelines(lines)
PY
  fi
  echo "[+] Patched $(basename $d) Makefile"
done

# 4. Realtek drivers — make MODULE_IMPORT_NS unconditional
# Drivers gate it inside #if (LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)) but our 5.4 kernel needs it.
# 88x2bu and 8821cu have it inside an #if/#endif — strip the guard.
# rtl8188eus doesn't have it — add it after MODULE_LICENSE.
for d in /work/88x2bu-20210702 /work/8821cu-20210916; do
  F=$d/os_dep/linux/os_intfs.c
  # Remove the #if line just above MODULE_IMPORT_NS, leave the import unconditional
  sed -i "/^#if.*LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)/d" $F
  # Remove the matching #endif on the line after MODULE_IMPORT_NS
  python3 - "$F" <<'PY'
import sys, re
fn = sys.argv[1]
with open(fn) as f: src = f.read()
# Pattern: MODULE_IMPORT_NS(...)\n#endif → just MODULE_IMPORT_NS(...)
src = re.sub(
    r'(MODULE_IMPORT_NS\(VFS_internal_I_am_really_a_filesystem_and_am_NOT_a_driver\);)\s*\n#endif\s*\n',
    r'\1\n', src
)
with open(fn, "w") as f: f.write(src)
PY
  echo "[+] Made MODULE_IMPORT_NS unconditional in $(basename $d)"
done

# rtl8188eus — add MODULE_IMPORT_NS after MODULE_LICENSE if missing
F=/work/rtl8188eus/os_dep/linux/os_intfs.c
if ! grep -q "MODULE_IMPORT_NS" $F; then
  sed -i "/^MODULE_LICENSE/a MODULE_IMPORT_NS(VFS_internal_I_am_really_a_filesystem_and_am_NOT_a_driver);" $F
  echo "[+] Added MODULE_IMPORT_NS to rtl8188eus"
fi

echo "[+] All patches applied."
EOF
