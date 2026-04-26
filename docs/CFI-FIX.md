# Realtek CFI Signature Fix (PR #1041)

## Why this exists

Linux kernel CFI (Control Flow Integrity, `CONFIG_CFI_CLANG`) hashes every function's signature at compile time. When code makes an indirect call through a function pointer, the runtime checks the called function's hash matches the call-site's expected hash. **Mismatch → kernel panic.**

CFI is required on this build because LineageOS 23.2 vendor modules (sensors, audio, networking) won't load on a CFI=off kernel.

The Realtek out-of-tree drivers (`rtl8188eus`, `88x2bu-20210702`, `8821cu-20210916`) install their callbacks via:

| Path | Indirect call expects | Realtek defines |
|------|-----------------------|-----------------|
| `tasklet_init(&t, usb_recv_tasklet, ...)` | `void(*)(unsigned long)` | `void usb_recv_tasklet(void *priv)` ❌ |
| `netdev_ops->ndo_start_xmit = rtw_xmit_entry` | `netdev_tx_t(*)(struct sk_buff*, struct net_device*)` | `int rtw_xmit_entry(_pkt*, _nic_hdl)` ❌ |

`_pkt` and `_nic_hdl` are typedefs that resolve to `struct sk_buff` and `struct net_device` — the *type tag* differs, which is enough for CFI to flag the call. Same for `int` vs `netdev_tx_t` (a typed enum).

When a frame is received via USB and the driver schedules `usb_recv_tasklet`, or when `iw set type monitor` triggers a code path that builds a TX skb and pushes through `ndo_start_xmit` — CFI hashes don't match → panic → reboot.

This is **exactly the panic** seen on `iw dev wlan1 set type monitor` in our build.

## The fix (GeorgeBannister / aircrack-ng PR #1041)

Six changes per driver, all source-level signature alignments:

```diff
--- include/usb_ops_linux.h
-void usb_recv_tasklet(void *priv);
+void usb_recv_tasklet(unsigned long priv);

--- os_dep/linux/usb_ops_linux.c     (2 occurrences — wrapped in #ifdef USB_PACKET_OFFSET_SZ)
-void usb_recv_tasklet(void *priv) {
+void usb_recv_tasklet(unsigned long priv) {
   ...
-  PADAPTER padapter = (PADAPTER)priv;
+  PADAPTER padapter = (PADAPTER)(uintptr_t)priv;
   ...
 }

--- os_dep/linux/xmit_linux.c
-int _rtw_xmit_entry(_pkt *pkt, _nic_hdl pnetdev)
+netdev_tx_t _rtw_xmit_entry(struct sk_buff *pkt, struct net_device *pnetdev)
 { ... }

-int rtw_xmit_entry(_pkt *pkt, _nic_hdl pnetdev)
+netdev_tx_t rtw_xmit_entry(struct sk_buff *pkt, struct net_device *pnetdev)
 {
-    int ret = 0;
+    netdev_tx_t ret = NETDEV_TX_OK;
     ...
     return ret;
 }

--- include/xmit_osdep.h
-extern int _rtw_xmit_entry(_pkt *pkt, _nic_hdl pnetdev);
-extern int rtw_xmit_entry(_pkt *pkt, _nic_hdl pnetdev);
+extern netdev_tx_t _rtw_xmit_entry(struct sk_buff *pkt, struct net_device *pnetdev);
+extern netdev_tx_t rtw_xmit_entry(struct sk_buff *pkt, struct net_device *pnetdev);
```

After applying + rebuilding the modules against a CFI=on kernel, indirect calls through these function pointers carry **matching signatures** → no CFI panic. Verified working: `iw set type monitor` + `tcpdump -i wlan1` capture WPA2 frames in air without any reboot.

## How this is applied automatically

`scripts/03-apply-patches.sh` includes a sed/awk pass over all 3 driver source trees:

```bash
for d in /work/rtl8188eus /work/88x2bu-20210702 /work/8821cu-20210916; do
  sed -i 's/void usb_recv_tasklet(void \*priv)/void usb_recv_tasklet(unsigned long priv)/g' \
      $d/include/usb_ops_linux.h \
      $d/os_dep/linux/usb_ops_linux.c
  # rtw_xmit_entry signature
  sed -i 's/int _rtw_xmit_entry(_pkt \*pkt, _nic_hdl pnetdev)/netdev_tx_t _rtw_xmit_entry(struct sk_buff *pkt, struct net_device *pnetdev)/g' \
      $d/os_dep/linux/xmit_linux.c \
      $d/include/xmit_osdep.h
  sed -i 's/int rtw_xmit_entry(_pkt \*pkt, _nic_hdl pnetdev)/netdev_tx_t rtw_xmit_entry(struct sk_buff *pkt, struct net_device *pnetdev)/g' \
      $d/os_dep/linux/xmit_linux.c \
      $d/include/xmit_osdep.h
  # ret type inside rtw_xmit_entry
  awk -v inside=0 '
    /^netdev_tx_t rtw_xmit_entry\(/ { inside=1 }
    inside && /^\tint ret = 0;/ { print "\tnetdev_tx_t ret = NETDEV_TX_OK;"; next }
    inside && /^}/ { inside=0 }
    { print }
  ' $d/os_dep/linux/xmit_linux.c > /tmp/x && mv /tmp/x $d/os_dep/linux/xmit_linux.c
done
```

## Manual verification

After patching, sanity-check from the container:

```bash
docker exec spacewar-build bash -c '
for d in /work/rtl8188eus /work/88x2bu-20210702 /work/8821cu-20210916; do
  echo --- $(basename $d) ---
  grep -c "unsigned long priv" $d/include/usb_ops_linux.h           # → 1
  grep -c "unsigned long priv" $d/os_dep/linux/usb_ops_linux.c      # → 2
  grep -c "netdev_tx_t rtw_xmit_entry" $d/include/xmit_osdep.h      # → 2
  grep -c "netdev_tx_t rtw_xmit_entry" $d/os_dep/linux/xmit_linux.c # → 1
done
'
```

If any line returns 0, the patch wasn't applied for that file.

## Backup patches as `.patch` files

`artifacts/realtek-patches/{rtl8188eus,88x2bu-20210702,8821cu-20210916}-cfi-fix.patch` — full diffs from a clean checkout. To re-apply on a fresh PC:

```bash
cd /work/rtl8188eus && git apply /work/artifacts/realtek-patches/rtl8188eus-cfi-fix.patch
cd /work/88x2bu-20210702 && git apply /work/artifacts/realtek-patches/88x2bu-20210702-cfi-fix.patch
cd /work/8821cu-20210916 && git apply /work/artifacts/realtek-patches/8821cu-20210916-cfi-fix.patch
```

## Open question — QCACLD inject CFI fix

The same class of CFI signature mismatch exists in the QCACLD-3.0 (Qualcomm internal WiFi) inject codepath, and crashes the kernel when standard tools like `aireplay-ng` or `hostapd` attempt to inject TX frames. **No source patch exists yet** — fixing this requires reading stack traces from a panic dump and aligning function pointer signatures throughout the inject path.

For now, the practical workaround is to use **WN722N (Realtek)** for inject scenarios; internal WiFi is fine for monitor / capture / scan.
