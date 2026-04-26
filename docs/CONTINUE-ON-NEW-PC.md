# Continuing on a new PC

This document is the resume-point for picking up work on a different machine.

## What's already done (no need to redo)

- ✅ **Stage 4 kernel persisted on phone slot_a** — `5.4.302-qgki-g192e5b024436-dirty`, CFI=on + LTO=on, Kali QCACLD inject 17 patches, NetHunter-style. Reboots into this every time. Don't reflash unless you want to.
- ✅ **Realtek modules with CFI fix loaded automatically** via Magisk module `realtek-wifi-cfi-fix-v1.0`. After phone reboot, `lsmod | grep -E '8188|8821|88x2bu'` shows them live.
- ✅ **Kali NetHunter chroot** at `/data/local/nhsystem/kali-arm64`. Has `aircrack-ng`, `tcpdump`, `iw`, `wireless-tools`. Enter with `chroot /data/local/nhsystem/kali-arm64 /bin/bash` after setting PATH.
- ✅ **NetHunter Manager + Store + Terminal apps** installed.

## What's saved in this repo (the source of truth)

```
.
├── README.md                    ← project overview (read this first)
├── running-config.gz            ← deterministic kernel config from running Stage 4
├── artifacts/
│   ├── Module.symvers           ← kernel symbol CRCs (matches running kernel)
│   ├── kernel.config            ← gunzipped running config (readable)
│   ├── kernel.release           ← "5.4.302-qgki-g192e5b024436-dirty"
│   └── realtek-patches/         ← CFI signature fix .patch files (per-driver)
├── output/
│   ├── modules-FINAL/           ← FINAL working .ko (vermagic matches phone)
│   ├── realtek-wifi-cfi-fix-v1.0.zip   ← Magisk module (auto-load on boot)
│   ├── stage4-los-plus-inject-boot.img ← what's on slot_a — disaster recovery
│   └── wlan.ko                  ← QCACLD wlan.ko for con_mode=4 internal monitor
├── modules/                     ← duplicate of output/modules-FINAL/ (kept in sync)
├── installers/                  ← Magisk + NetHunter + NetHunterStore APKs
├── lineage-23.2-spacewar/       ← LOS install zip + base partition images
├── local-backup-pristine-...    ← full phone partition backup (6.9 GB)
├── docs/
│   ├── BUILD-LOG-2026-04-26.md  ← THE comprehensive timeline + bug catalogue
│   ├── CFI-FIX.md               ← PR #1041 explained — what the Realtek patches do
│   ├── INTERNAL-WIFI-MONITOR.md ← con_mode=4 workflow for wlan0 monitor
│   ├── CONTINUE-ON-NEW-PC.md    ← (this file)
│   ├── BUILD.md / FLASH.md / DIAGNOSTICS.md ← original repo docs
│   └── MERCUSYS-USB-MODESWITCH.md
└── scripts/
    ├── 01-setup-container.sh    ← creates `spacewar-build` Docker container
    ├── 02-clone-sources.sh      ← clones kernel + Realtek + AnyKernel3 + AOSP-Clang + kali-kernel-builder
    ├── 03-apply-patches.sh      ← all source patches incl. Realtek CFI fix
    ├── 04-configure.sh          ← reads running-config.gz from repo, applies olddefconfig
    ├── 05-build-kernel.sh       ← Image + dtbs + modules
    ├── 06-build-modules.sh      ← Realtek out-of-tree modules against /work/kernel-los/out
    └── 07-package-zip.sh        ← AnyKernel3 flashable zip (optional)
```

## Pick up on new PC — sequence

```bash
# 0. Clone repo (if not already there) and check out the same branch
git clone <this-repo>
cd nothing-phone-1-nethunter-kernel
# or just `cd` into your existing checkout

# 1. Install prerequisites — Docker Desktop + WSL2 + Git Bash + Android Platform Tools
#    (driver setup is handled by scripts/00-install-driver.cmd if you need fastboot)

# 2. Spin up the build container — fresh
scripts/01-setup-container.sh             # 10–20 min — pulls Ubuntu 22.04 + build deps

# 3. Clone all sources into /work/ in the container — fresh
scripts/02-clone-sources.sh               # 30–60 min (kernel ~3 GB; AOSP-Clang r536225 ~3 GB)

# 4. Apply patches — incl. Realtek CFI fix from PR #1041
scripts/03-apply-patches.sh               # ~1 min

# 5. Configure with the deterministic running config
scripts/04-configure.sh                   # ~30 sec — reads running-config.gz from repo root

# 6. Build kernel + in-tree modules
scripts/05-build-kernel.sh                # 13–15 min on 6 cores

# 7. Build Realtek out-of-tree modules
scripts/06-build-modules.sh               # 5–8 min for all 3

# 8. Verify vermagic matches what's on phone
docker exec spacewar-build bash -c '
  for f in /work/modules-FINAL/*.ko; do
    echo "$(basename $f): $(strings $f | grep -m1 vermagic)"
  done
'
# Expected: vermagic=5.4.302-qgki-g192e5b024436-dirty SMP preempt mod_unload modversions aarch64
```

If vermagic matches → you can `adb push` the new modules to `/data/local/tmp` and `insmod` directly without reflashing boot.img, because the kernel running on slot_a is byte-identical to what you just built.

## Verify phone is in expected state

```bash
adb shell uname -r
# → 5.4.302-qgki-g192e5b024436-dirty

adb shell 'lsmod | grep -E "8188|8821|88x2bu"'
# → 8188eu and 8821cu loaded (Magisk module did its thing on boot)

adb shell 'su -c "ls /data/adb/modules/"'
# → realtek-wifi-cfi-fix

adb shell 'pm list packages | grep -i nethunter'
# → com.offsec.nethunter
# → com.offsec.nethunter.store
# → com.offsec.nhterm

adb shell 'su -c "ls /data/local/nhsystem/kali-arm64/etc/os-release"'
# → exists; chroot ready
```

## Disaster recovery

If something goes wrong, here's the layered fallback:

| Symptom | Recovery |
|---------|----------|
| Phone bootloops on slot_a | Flash `output/stage4-los-plus-inject-boot.img` to `boot_a` via `fastboot flash boot_a output/stage4-los-plus-inject-boot.img` |
| Phone won't boot at all | Reflash full phone from `lineage-23.2-spacewar/lineage-23.2-20260422-nightly-Spacewar-signed.zip` via recovery sideload |
| Magisk lost | Reinstall `installers/Magisk-v30.7.apk`, patch boot via Magisk UI, `fastboot flash boot_a` |
| Catastrophic — partition layout corrupted | Restore from `local-backup-pristine-20260426-1939/` via `fastboot flash <partition> <image>` for each partition |

## Tomorrow's likely tasks

In rough priority:
1. **Field-test 88x2bu (Asus USB-AC58)** in monitor + inject mode. Should work since the same CFI fix is applied.
2. **Field-test 8821cu (Mercusys MU-6H)** — first need USB mode-switch (the device shows up as a CD-ROM until switched). See `docs/MERCUSYS-USB-MODESWITCH.md`.
3. **Install full `kali-tools-wireless`** in chroot (~1 GB) — adds `wifite2`, `bettercap`, `hostapd-mana`, `mana-toolkit`, `reaver`, `bully`, `pixiewps`.
4. **Test internal WiFi inject via NetHunter app's UI** — should work via Kali netlink API (CFI-clean) where standalone `aireplay-ng` panics.
5. (Stretch) Begin work on **CFI fix patches for QCACLD inject** — would unlock internal WiFi inject without WN722N. Multi-hour task.

## Notes / gotchas

- **Always `export MSYS_NO_PATHCONV=1`** when using Git Bash on Windows + Docker. Otherwise `/work` becomes `C:/Program Files/Git/work` inside container.
- **Always use `docker exec -i`** with heredocs, never plain `docker exec` — without `-i`, stdin isn't piped.
- **WiFi adb port rotates** on Android 16. Each Wireless Debugging toggle gives a new random port. For predictable testing use USB.
- **Realtek WN722N v3** = USB ID `2357:010c` = chip RTL8188EUS = driver `8188eu.ko`. There are also v1/v2 with different chips — those need different drivers.
- **Mercusys MU-6H** is a CD-ROM until USB-modeswitched. The drivers on this kernel handle it (`8821cu.ko`).
- **Don't break Magisk slot_a** — the persisted Stage 4 kernel is the safety net.
