#!/bin/bash
# Apply source patches:
# 1. hh_msgq.h — fix three int functions returning ERR_PTR (pointer)
# 2. msm_cvp_ioctl.c — add missing #include <linux/compat.h>
# 3. Realtek drivers — make MODULE_IMPORT_NS unconditional, drop Wno-stringop-overread,
#    drop -DRTW_ENABLE_WIFI_CONTROL_FUNC
set -e
export MSYS_NO_PATHCONV=1   # Git Bash on Windows: stop /work being rewritten to C:/Program Files/Git/work

CONTAINER=spacewar-build

docker exec -i $CONTAINER bash <<'EOF'
set -e
export MSYS_NO_PATHCONV=1   # Git Bash on Windows: stop /work being rewritten to C:/Program Files/Git/work

# 0. Focaltech touchscreen firmware blob (FT3680_WXN_M146_V27_D01_20220706_app.i) — 598 KB header
#    Required by drivers/input/touchscreen/focaltech_touch/focaltech_flash.c at compile time.
#    Missing from kimocoder/android_kernel_lineage_nothing_sm7325 nethunter-23.0 source.
#    Pull it from kimocoder/android_kernel_msm-5.4_nothing_sm7325 (where it IS committed).
FW_DIR=/work/kernel-los/drivers/input/touchscreen/focaltech_touch/include/firmware
FW_FILE=$FW_DIR/FT3680_WXN_M146_V27_D01_20220706_app.i
if [ ! -s "$FW_FILE" ]; then
  mkdir -p "$FW_DIR"
  curl -sLf "https://raw.githubusercontent.com/kimocoder/android_kernel_msm-5.4_nothing_sm7325/nethunter-15.0/drivers/input/touchscreen/focaltech_touch/include/firmware/FT3680_WXN_M146_V27_D01_20220706_app.i" \
    -o "$FW_FILE"
  echo "[+] Pulled missing Focaltech firmware blob ($(wc -c < "$FW_FILE") bytes)"
fi
# fw_sample.i is the secondary firmware placeholder (FW2/FW3 both point at it). Upstream is 0 bytes — touch.
touch "$FW_DIR/fw_sample.i"

# 1. haven/hh_msgq.h — three stub functions return wrong type (int returning void* via ERR_PTR)
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

# 3. Realtek drivers — Makefile fixes
for d in /work/rtl8188eus /work/88x2bu-20210702 /work/8821cu-20210916; do
  # Remove -Wno-stringop-overread (Clang doesn't recognize on older versions)
  sed -i 's/-Wno-stringop-overread//g' $d/Makefile
  # Remove -Wno-enum-int-mismatch (GCC-only, AOSP Clang errors out as -Werror=unknown-warning-option)
  sed -i 's/-Wno-enum-int-mismatch//g' $d/Makefile
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

# 4.5. CFI signature fix (PR #1041 by GeorgeBannister) — REQUIRED for CFI=on kernels.
#      Without this, `iw set type monitor` on Realtek wlan kernel-panics on CFI=on.
#      Aligns function pointer signatures kernel CFI expects:
#         tasklet callback:   void(*)(unsigned long)        (was void(*)(void*))
#         ndo_start_xmit:     netdev_tx_t(*)(skb*, netdev*) (was int(*)(_pkt*, _nic_hdl))
#      See docs/CFI-FIX.md for full explanation.
echo "[*] Applying Realtek CFI signature fix (PR #1041)"
for d in /work/rtl8188eus /work/88x2bu-20210702 /work/8821cu-20210916; do
  # tasklet signature
  sed -i 's/void usb_recv_tasklet(void \*priv)/void usb_recv_tasklet(unsigned long priv)/g' \
      $d/include/usb_ops_linux.h \
      $d/os_dep/linux/usb_ops_linux.c
  # rtw_xmit_entry signature — declarations
  sed -i 's/extern int _rtw_xmit_entry(_pkt \*pkt, _nic_hdl pnetdev)/extern netdev_tx_t _rtw_xmit_entry(struct sk_buff *pkt, struct net_device *pnetdev)/g' \
      $d/include/xmit_osdep.h
  sed -i 's/extern int rtw_xmit_entry(_pkt \*pkt, _nic_hdl pnetdev)/extern netdev_tx_t rtw_xmit_entry(struct sk_buff *pkt, struct net_device *pnetdev)/g' \
      $d/include/xmit_osdep.h
  # rtw_xmit_entry signature — definitions
  sed -i 's/^int _rtw_xmit_entry(_pkt \*pkt, _nic_hdl pnetdev)/netdev_tx_t _rtw_xmit_entry(struct sk_buff *pkt, struct net_device *pnetdev)/g' \
      $d/os_dep/linux/xmit_linux.c
  sed -i 's/^int rtw_xmit_entry(_pkt \*pkt, _nic_hdl pnetdev)/netdev_tx_t rtw_xmit_entry(struct sk_buff *pkt, struct net_device *pnetdev)/g' \
      $d/os_dep/linux/xmit_linux.c
  # ret type inside rtw_xmit_entry — only change the FIRST `int ret = 0;` after the signature line
  awk -v changed=0 '
    /^netdev_tx_t rtw_xmit_entry\(/ { in_func=1 }
    in_func && !changed && /^[[:space:]]*int ret = 0;[[:space:]]*$/ {
      sub(/int ret = 0;/, "netdev_tx_t ret = NETDEV_TX_OK;")
      changed=1
    }
    in_func && /^}/ { in_func=0 }
    { print }
  ' $d/os_dep/linux/xmit_linux.c > $d/os_dep/linux/xmit_linux.c.new && \
    mv $d/os_dep/linux/xmit_linux.c.new $d/os_dep/linux/xmit_linux.c
  echo "[+] CFI fix applied to $(basename $d)"
done

# Sanity-check: each driver should match these counts
for d in /work/rtl8188eus /work/88x2bu-20210702 /work/8821cu-20210916; do
  c1=$(grep -c "unsigned long priv" $d/include/usb_ops_linux.h)
  c2=$(grep -c "unsigned long priv" $d/os_dep/linux/usb_ops_linux.c)
  c3=$(grep -c "netdev_tx_t rtw_xmit_entry" $d/include/xmit_osdep.h)
  c4=$(grep -c "netdev_tx_t rtw_xmit_entry" $d/os_dep/linux/xmit_linux.c)
  printf "    %-22s usb_recv_tasklet h=%d c=%d  rtw_xmit_entry h=%d c=%d\n" \
         "$(basename $d):" $c1 $c2 $c3 $c4
done
# Expected: h=1 c=2  h=2 c=1   for each driver. Anything else = patch didn't take.

# 3.5. Relax strict warnings in qcacld-3.0 Kbuild — needed because the Kali inject patch
#      (next step) uses old enum types that newer lineage qcacld-3.0 doesn't allow under
#      -Werror=enum-conversion / -Werror=enum-int-mismatch.
QCACLD_KBUILD=/work/kernel-los/drivers/staging/qcacld-3.0/Kbuild
if ! head -1 "$QCACLD_KBUILD" | grep -q "Wno-enum-conversion"; then
  # Just -Wno-enum-conversion — the -Werror= variants are GCC-only and AOSP Clang refuses them.
  sed -i "1i ccflags-y += -Wno-enum-conversion" "$QCACLD_KBUILD"
  echo "[+] Relaxed enum-conversion warnings in qcacld-3.0/Kbuild"
fi

# 4. Kali NetHunter QCACLD-3.0 packet injection patch series (17 patches).
#    Adds wlan_hdd_frame_inject.{c,h}, wlan_hdd_inject_security.{c,h},
#    wlan_hdd_frame_validate.{c,h}, wma_frame_inject.c + Kbuild + defconfig flag.
#    Patch 02/17 is already cherry-picked into lineage nethunter-23.0;
#    `git am --3way` skips already-applied hunks; loop --skip on conflicts so
#    the remaining 16 patches still go in.
PATCH=/work/kali-kernel-builder/patches/5.4/add-qcacld-3.0-injection-5.4.patch
if [ -f "$PATCH" ]; then
  cd /work/kernel-los
  git config user.email "build@spacewar-nethunter.local"
  git config user.name  "spacewar-nethunter-build"

  set +e
  git am --3way --keep-cr "$PATCH"
  rc=$?
  guard=0
  while [ $rc -ne 0 ] && [ -d .git/rebase-apply ] && [ $guard -lt 20 ]; do
    echo "[!] Hunk already applied or trivial conflict — skipping current patch"
    git am --skip
    rc=$?
    guard=$((guard + 1))
  done
  if [ -d .git/rebase-apply ]; then
    # 20 skips and still stuck → bail out cleanly
    git am --abort
    echo "[!] git am could not finish; falling back to patch -p1 --forward"
    patch -p1 --forward --no-backup-if-mismatch -i "$PATCH" || true
  fi
  set -e
  cd - >/dev/null
  echo "[+] Kali QCACLD-3.0 injection patch series applied"
else
  echo "[!] WARNING: Kali QCACLD inject patch not found at $PATCH"
  echo "    Internal Wi-Fi packet injection won't be available."
fi

echo "[+] All patches applied."
EOF
