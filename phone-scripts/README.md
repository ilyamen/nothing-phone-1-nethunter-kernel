# Phone-side automation

Two pieces of automation that live on the phone (not the PC):

1. **`magisk-modules/nh-wifi-adb/`** — Magisk module that auto-starts `adbd` on TCP port `44444` every boot. Install once via Magisk Manager → enable. Reboot. Connect from PC: `adb connect <phone-ip>:44444`.

2. **`termux-widget/*.sh`** — shell scripts to run from a Termux:Widget shortcut on the home screen (one tap = run command + show output). Use this for ad-hoc actions that you don't want auto-running every boot:
   - `mercusys-switch.sh` — flip Mercusys MU-6H from CD-ROM to WiFi mode (run after plugging in)
   - `internal-monitor-on.sh` — switch internal wlan0 to monitor mode via `con_mode=4` reload
   - `internal-monitor-off.sh` — return wlan0 to STA mode
   - `kali-shell.sh` — drop into Kali NetHunter chroot

Add more scripts here for any pen-test workflow you find yourself running often.

## Install

### Magisk module (`nh-wifi-adb`)

The module is in `magisk-modules/nh-wifi-adb/`. To produce a flashable zip on PC:

```bash
cd magisk-modules/nh-wifi-adb
zip -r ../nh-wifi-adb.zip . -x "*.git*"
adb push ../nh-wifi-adb.zip /sdcard/Download/
```

On phone: open Magisk Manager → Modules → Install from storage → pick `nh-wifi-adb.zip` → reboot.

After reboot ADB is on `:44444` automatically. Disable the module (toggle in Magisk) to stop the auto-start.

### Termux + Termux:Widget

Install both apps from F-Droid (NOT Play Store — Play Store version is outdated and lacks the right APIs):
- https://f-droid.org/packages/com.termux/
- https://f-droid.org/packages/com.termux.widget/

Open Termux once to let it bootstrap, then grant it root via Magisk Manager → Settings → Magisk Permissions → Termux → allow.

Copy the scripts into `~/.shortcuts/`:

```bash
# In Termux on phone:
mkdir -p ~/.shortcuts
# Use any file manager (Material Files, MiXplorer) to copy *.sh from this repo
# Or via adb:
#   adb push phone-scripts/termux-widget/*.sh /sdcard/
#   then in Termux: cp /sdcard/*.sh ~/.shortcuts/ && chmod +x ~/.shortcuts/*.sh
```

Long-press home screen → Widgets → Termux:Widget → drag a `Termux Shortcut` onto the desktop. Pick a script. Done — one tap = run it.

For richer GUI you can also try:
- **Material Files** (file manager with built-in terminal & shortcuts)
- **MiXplorer** (Pro-grade file manager with a Terminal addon)
- **AppShortcut** (any app supports launchable shortcuts via Activities — not strictly needed)

## Adding new scripts

1. Drop a `.sh` in `phone-scripts/termux-widget/`
2. Make it `chmod +x` on the phone (in `~/.shortcuts/`)
3. Termux:Widget auto-discovers it on next refresh of the widget

Scripts run as the Termux user. Use `su -c "..."` for root commands.
