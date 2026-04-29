# NetHunter Kernel — Roadmap (post-v1.0.0)

What didn't make v1.0.0, ranked by impact for the typical Wi-Fi/LAN-pentest workflow on this device. Status verified against the live kernel config (`/proc/config.gz`) shipped in v1.0.0.

Legend:
- 🔴 blocked by GKI vendor ABI on LOS 23.2 (cannot enable on this image)
- 🟡 missing, can be enabled in next image
- ⏭ userspace / Magisk module work — no kernel rebuild needed
- ✅ already in v1.0.0 (listed for completeness when category mixes)

---

## P0 — significant attack surface gaps, prioritise for v1.1

### 1. `nftables` (NF_TABLES) — 🟡

```
CONFIG_NF_TABLES=NOT_SET
CONFIG_NFT_COMPAT=NOT_SET
CONFIG_NFT_NAT=NOT_SET
```

iptables works. nftables (the modern replacement, default in Debian 11+ / Kali rolling) does not. Modern Kali tools and any tooling that calls `nft` directly will fail. Trivial to add — kconfig dependency chain is just `NETFILTER → NF_TABLES → NFT_*`.

### 2. Bridge + L2 MITM (BRIDGE_NETFILTER, EBT tables) — 🟡

```
CONFIG_BRIDGE=y                  ✅
CONFIG_BRIDGE_EBT_BROUTE=y       ✅ (limited)
CONFIG_BRIDGE_NETFILTER=NOT_SET  🟡
CONFIG_BRIDGE_EBT_T_FILTER=NOT_SET   🟡
CONFIG_BRIDGE_EBT_T_NAT=NOT_SET      🟡
CONFIG_BRIDGE_VLAN_FILTERING=NOT_SET 🟡
```

Without `BRIDGE_NETFILTER`, `iptables` rules don't apply to bridged frames — the classic "phone-as-transparent-bridge between target and switch" MITM scenario is crippled. We have a bridge, but without filter/nat tables and without bridge↔netfilter integration the L2 attack surface is half-functional.

### 3. 802.1Q VLAN (VLAN_8021Q) — 🟡

```
CONFIG_VLAN_8021Q=NOT_SET        🟡
CONFIG_VLAN_8021Q_GVRP=NOT_SET   🟡
CONFIG_VLAN_8021Q_MVRP=NOT_SET   🟡
```

Phone cannot tag/untag VLANs from kernel. VLAN-hopping attacks (double-tag, native VLAN abuse) impossible from this device. In a LAN pentest with trunked switches this is a real gap.

### 4. User / PID / IPC namespaces (Docker/rootless) — 🟡

```
CONFIG_NAMESPACES=y     ✅
CONFIG_NET_NS=y         ✅
CONFIG_UTS_NS=y         ✅
CONFIG_USER_NS=NOT_SET  🟡
CONFIG_PID_NS=NOT_SET   🟡
CONFIG_IPC_NS=NOT_SET   🟡
```

Docker / podman / rootless containers do **not** work. Modern pentest workflows use containerized tooling; we can't run them natively. Multi-chroot (Kali + Parrot) won't isolate. `OVERLAY_FS=y` is already there, so adding the three NS flags is enough.

### 5. RTL8812AU (Alfa AWUS036ACH) — 🟡 / out-of-tree

The most popular AC1200 pentest USB Wi-Fi dongle in the wild. We ship out-of-tree drivers for RTL8188EUS / RTL8812BU / RTL8821CU but not 8812AU (different chip, different driver source: `aircrack-ng/rtl8812au`). Add as fourth Magisk module with the same CFI patching pattern.

---

## P1 — high value, plan for v1.1 or v1.2

### 6. MT76 USB family — 🟡

```
CONFIG_MT7601U=m       ✅ (older N300)
CONFIG_MT76_USB=NOT_SET  🟡
CONFIG_MT76x0U=NOT_SET   🟡 (MT7610U USB AC600)
CONFIG_MT76x2U=NOT_SET   🟡 (MT7612U USB AC1200)
CONFIG_MT7921U=NOT_SET   🟡 (Wi-Fi 6 — likely backportable)
```

MT76 USB Wi-Fi 6 dongles are the modern alternative to Realtek out-of-tree mess. In-kernel, no CFI patches needed. We have the framework (MT7601U pulls in mac80211/cfg80211 dependencies); adding USB child drivers is `make menuconfig` plus rebuild.

### 7. Tunneling / overlay (VXLAN, GENEVE) — 🟡

```
CONFIG_NET_IPGRE=y     ✅
CONFIG_IPV6_GRE=y      ✅
CONFIG_IPV6_TUNNEL=y   ✅
CONFIG_VXLAN=NOT_SET    🟡
CONFIG_GENEVE=NOT_SET   🟡
CONFIG_GTP=NOT_SET      🟡
CONFIG_NET_FOU=NOT_SET  🟡
CONFIG_IPV6_MROUTE=NOT_SET 🟡
```

GRE works for legacy tunnels; VXLAN/GENEVE/GTP/FOU for modern overlay attacks (Kubernetes lateral movement, cellular GTP). Lower priority for pure red-team Wi-Fi work, higher for cloud/cellular pentest.

### 8. Magisk modules: pentest infrastructure — ⏭

Top three popular community modules we *don't* ship:
- **Frida-server module** — auto-launches `frida-server` listening on 27042. Kprobes/uprobes already in kernel (✅) so it'd work.
- **Burp Suite CA installer** — pushes user CA into `/system/etc/security/cacerts/` so Burp can MITM HTTPS without per-app pinning bypass.
- **SSL pinning bypass** — Frida script + objection runner. Most-asked for Android pentest.

Pure Magisk module work, no kernel involved.

### 9. RTL8XXXU (in-kernel Realtek combo USB) — 🟡

```
CONFIG_RTL8XXXU=NOT_SET  🟡
```

In-kernel driver for Realtek combo BT+Wi-Fi USB chips: RTL8723BU, RTL8821AU, RTL8188FU. Unlike our out-of-tree modules these don't need CFI patches. Useful for cheap combo dongles where you want both BT *and* Wi-Fi from one device.

---

## P2 — medium value

### 10. Function tracer / advanced ftrace — 🟡

```
CONFIG_FTRACE=y                ✅
CONFIG_KPROBES=y               ✅
CONFIG_UPROBES=y               ✅
CONFIG_FUNCTION_TRACER=NOT_SET     🟡
CONFIG_FTRACE_SYSCALLS=NOT_SET     🟡
CONFIG_HIST_TRIGGERS=NOT_SET       🟡
CONFIG_HAVE_KPROBES_ON_FTRACE=NOT_SET 🟡
```

ftrace skeleton is there but function-level tracing is not. We can probe via kprobes (the more flexible primitive), so this is incremental, not blocking.

### 11. NetHunter app preset library — ⏭

Stock NetHunter app ships empty Custom Commands / HID Attacks / DuckHunter / MITM Framework presets. Third-party kernels often provide curated payload bundles. None bundled here.

### 12. Kali chroot pre-bundled — ⏭

Currently users run "Chroot Manager → Download" (~1.5 GB). Could ship `kali-arm64-rootfs.tar.xz` as a release asset, but GitHub release per-file limit is 2 GB and total of 219 MB → +1.5 GB pushes the release page heavy.

### 13. NETLINK_DIAG — 🟡

```
CONFIG_NETLINK_DIAG=NOT_SET  🟡
```

Netlink socket inspection. Tools that introspect netlink (e.g. systemd-internal monitors, some routing-attack tools) need this.

---

## P3 — low value / niche

### 14. Old / niche Wi-Fi USB drivers — 🟡

```
CONFIG_CARL9170=NOT_SET    (old Atheros AR9170 USB)
CONFIG_ZD1211RW=NOT_SET    (old ZyDAS)
CONFIG_RT2500USB=NOT_SET   (old Ralink)
CONFIG_RT73USB=NOT_SET     (old Ralink)
```

Ancient hardware. Skip unless someone files an issue.

### 15. Debug kernel variant (KASAN/KGDB/KFENCE) — 🟡

```
CONFIG_KASAN=NOT_SET
CONFIG_KCSAN=NOT_SET
CONFIG_KFENCE=NOT_SET
CONFIG_KGDB=NOT_SET
CONFIG_PROC_KCORE=NOT_SET
CONFIG_PROVE_LOCKING=NOT_SET
```

A separate debug-variant boot.img (`-debug` suffix) for kernel-bug investigation. Big build (debug symbols + sanitizer overhead) and not needed for typical end users; ship-on-demand.

### 16. CAN bus — 🔴 BLOCKED (cannot enable)

```
CONFIG_CAN, CAN_VCAN, SLCAN — all 🔴
```

Adds a field to `struct net` → breaks LOS 23.2 vendor `.ko` ABI, vendor modules fail to load, system_server crashes. Documented in v1.0.0 release notes as "use out-of-tree `.ko` build" if you really need it.

### 17. CFG80211_WEXT — 🔴 BLOCKED

```
CONFIG_CFG80211_WEXT=NOT_SET 🔴
```

Adds field to `struct wiphy` → vendor wlan ABI break.

### 18. MAC80211_MESH — 🔴 BLOCKED

Same as WEXT — wiphy ABI break. 802.11s mesh attacks not possible from this kernel.

---

## Already covered for Wi-Fi/LAN pentest (✅ in v1.0.0)

For reference:

**Wi-Fi USB drivers in-kernel:**
- `ATH9K_HTC=m` — AR9271 (TP-Link WN722N v1, Alfa AWUS036NHA)
- `ATH10K_USB=m` — Atheros 802.11ac USB
- `MT7601U=m` — MediaTek N300
- `RT2800USB=m` — Ralink RT3070/RT5370 (Alfa AWUS036NH)

### ✅ Internal Wi-Fi monitor mode — works via sysfs `con_mode`

Internal Qualcomm WCN6855 monitor mode + frame injection **work end-to-end**, but **activation is NOT via `iw set type` / `airmon-ng`**. The Kali QCACLD-3.0 patches deliberately bypass standard `iw` and route mode switches through a sysfs module parameter (commit `7bf1f20`: "Asynchronous synchronization of Wi-Fi mode (STA/MONITOR), **bypassing iw commands**").

**Correct activation:**

```sh
svc wifi disable
ip link set wlan0 down
echo 4 > /sys/module/wlan/parameters/con_mode    # 4 = Monitor, 0 = STA
ip link set wlan0 up
iw dev wlan0 info | grep type                    # → type monitor ✓
```

**Wrong activation (what every Linux desktop tutorial says — DOES NOT WORK on QCACLD):**
```sh
iw dev wlan0 set type monitor      # → ENOTSUPP (-95). By design.
airmon-ng start wlan0              # → tries to add new mon interface, fails -22.
iw dev wlan0 interface add mon0 type monitor   # → -22.
```

What works on internal Wi-Fi after `con_mode=4`:
- ✅ Full monitor mode capture (airodump-ng, tcpdump, etc.)
- ✅ Frame injection (aireplay-ng deauth, packetforge-ng)
- ✅ Channel hopping (`iw dev wlan0 set channel <N>` works in monitor mode)

External USB adapters (RTL8188EUS / RTL8812BU / RTL8821CU via `realtek-wifi-cfi-fix` Magisk module) still useful when:
- You want internal Wi-Fi to keep serving Android data connection while sniffing
- Multiple simultaneous monitor interfaces needed
- Higher TX power / external antenna desired

**Wi-Fi USB out-of-tree (Magisk module `realtek-wifi-cfi-fix`):**
- RTL8188EUS, RTL8812BU, RTL8821CU/8811CU

**Wi-Fi stack:**
- `MAC80211_HWSIM=m` — Karma / virtual APs
- `NL80211_TESTMODE=y` — extended testmode commands
- Internal Qualcomm WCN6855 — monitor + injection via Kali QCACLD patches

**LAN pentest:**
- TPROXY full stack (`XT_TARGET_TPROXY` + `NF_TPROXY_IPV4` + `NF_TPROXY_IPV6`) — mitmproxy works
- NAT / MASQUERADE / REDIRECT / CONNTRACK / NFQUEUE / NFLOG
- IPGRE / IPV6_GRE / IPV6_TUNNEL / IPV6_SIT — basic tunnels
- BPF + JIT + KPROBES + UPROBES — Frida-server, scapy/nfqueue, eBPF probes
- PACKET + PACKET_DIAG — pcap

**Bluetooth USB:**
- `BT_HCIBTUSB` with `BCM`, `MTK`, `RTL` quirks — covers Broadcom, MediaTek, Realtek BT dongles
- `BT_HCIVHCI=m` — virtual HCI for btproxy / userspace HCI

**Filesystems:**
- EXFAT, F2FS, EROFS, FUSE, OVERLAY_FS — all `=y`
- NFS_V2/V3 client, NFSD V3+V4 server — present
- NTFS+CIFS via Magisk module `nh-batch5-storage`

---

---

## Windows LAN pentest — specifics

The realistic deployment target for this build is "phone in someone's Windows-heavy office network, attacking AD". Audit on this axis:

### ✅ Kernel-side already strong

```
CONFIG_CIFS=m                        SMB client
CONFIG_CIFS_UPCALL=y                 Kerberos / NTLM credentials via keyring
CONFIG_CIFS_DFS_UPCALL=y             DFS namespace traversal
CONFIG_CIFS_POSIX=y, CIFS_XATTR=y    POSIX + xattr extensions
CONFIG_CIFS_ALLOW_INSECURE_LEGACY=y  SMB1 enabled (for legacy XP/2003 in corp nets)
CONFIG_NF_CONNTRACK_NETBIOS_NS=y     NetBIOS Name Service connection tracking
CONFIG_KEYS=y                        kernel keyring (cifs.upcall + krb5)
CONFIG_PPP_MPPE=y                    Microsoft PPP encryption
CONFIG_IPV6=y + IP6_NF_IPTABLES=y    mitm6 attack path
CONFIG_USB_CONFIGFS_F_HID=y          BadUSB → keyboard injection on Windows
CONFIG_USB_CONFIGFS_MASS_STORAGE=y   DriveDroid USB spoof
CONFIG_USB_CONFIGFS_RNDIS=y          Phone-as-USB-Ethernet on Windows (instant MITM)
TPROXY full stack                    ntlmrelayx, Responder transparent redirect
```

The CIFS client is exceptionally well-configured — **SMB1 explicitly allowed** — covering legacy targets that modern distros disable by default.

### 🟡 Minor kernel gaps for Win-LAN

| Flag | Impact |
|------|--------|
| `IP6_NF_NAT, IP6_NF_TARGET_MASQUERADE` | No IPv6 NAT — mitm6 usually works without it (RA spoof on same L2), but SNAT/DNAT-over-IPv6 not possible |
| `KEYS_REQUEST_CACHE, BIG_KEYS, PERSISTENT_KEYRINGS` | Large Kerberos tickets / persistent caches across processes |
| `SOCK_DIAG` | `ss` tool limited socket introspection |
| `NETFILTER_XT_MATCH_DHCP` | No DHCP iptables match (workaround: `u32` + dport 67/68) |

### ⏭ Userspace — the actual gap (we ship none of these)

All Windows-AD tooling is userspace inside Kali chroot. We don't pre-install. User does `apt install` after `Chroot Manager → Update Chroot`. Top tools:

- `responder` — LLMNR/NBT-NS/MDNS/WPAD poisoner (in default Kali)
- `crackmapexec` / `netexec` (nxc) — universal AD enumeration + lateral movement
- `impacket-*` — smbserver, ntlmrelayx, secretsdump, GetNPUsers, GetUserSPNs, wmiexec, psexec, atexec, dcomexec, lookupsid, rpcdump, rpcmap, ticketer, raiseChild, goldenPac
- `bloodhound.py` — AD graph collection
- `mitm6` — IPv6 RA spoof + DHCPv6 → NTLM relay
- `evil-winrm` — Windows Remote Management
- `enum4linux-ng` — SMB/RPC enumeration
- `kerbrute` (pip) — Kerberos pre-auth user enumeration / spraying
- `certipy` (pip) — AD CS abuse
- `bloodyAD` — AD object manipulation
- `PetitPotam` / `DFSCoerce` / `ShadowCoerce` — coercion attacks (manual python)
- `printerbug.py` — MS-RPRN coercion

### 🟡 What we *could* add specifically for Windows-LAN

These would land as Magisk modules or NetHunter app preset content — no kernel rebuild:

1. **Pre-pulled Kali pentest packages** — chroot-init hook that runs `apt install -y responder crackmapexec mitm6 bloodhound.py evil-winrm impacket-scripts enum4linux-ng` on first chroot creation. Saves 10-15 min of "wait for download" for every new install.
2. **HID payload library for Win10/11** — curated DuckHunter scripts covering: PowerShell one-liner reverse shell, AMSI patch, Defender bypass, UAC bypass via fodhelper / computerdefaults, scheduled-task persistence, mimikatz dropper.
3. **Mass Storage payload pack for DriveDroid** — pre-cached `.iso` / `.img` for Hiren's BootCD, Sergei Strelec WinPE, Kali Live, Win10 install ISO + autorun.cmd templates.
4. **NetHunter Custom Commands library** for AD scenarios:
   - "Responder 30min, dump hashes to /sdcard/loot/"
   - "mitm6 + ntlmrelayx targeting domain controller"
   - "BadUSB: Win10 PS reverse shell to <listener IP>"
   - "Coerce + relay PetitPotam → AD CS template"
5. **`nh-pentest-presets` Magisk module** — drops curated config templates into `/system/etc/nethunter-presets/`: `responder-corp.conf` (full poisoning), `responder-stealth.conf` (LLMNR-only), `ntlmrelayx-targets.json`, `mitm6-allowlist.txt`.
6. **Magisk module: `responder-autostart`** — when a specific SSID is connected, optionally auto-launch Responder with logging to /sdcard/responder-loot/. Trigger via NetHunter NhTrigger or Tasker integration.

### Bottom line for Win-LAN

Kernel side is solid and ready out-of-the-box for the standard SMB / NTLM-relay / mitm6 / BadUSB workflow. The real work is userspace — pre-installation of impacket+responder+crackmapexec, plus curated payload libraries. None of that is bundled today, but all of it is additive (Magisk modules + chroot-init hooks), no kernel rebuild needed for v1.1.

---

## Recommendation for v1.1 scope

If we cut a v1.1 next month, the cheapest-yet-impactful set is:

1. Enable `NF_TABLES`, `BRIDGE_NETFILTER`, `BRIDGE_EBT_T_FILTER/T_NAT`, `VLAN_8021Q`, `USER_NS`+`PID_NS`+`IPC_NS`, `MT76_USB`+`MT76x0U`+`MT76x2U` — all kconfig flag flips, one rebuild.
2. Add `rtl8812au` Magisk module (same template as existing Realtek modules).
3. Add `frida-server` Magisk module + `burp-ca-installer` Magisk module — pure userspace.

Ship as v1.1 minor bump.
