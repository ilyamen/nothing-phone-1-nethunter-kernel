#!/system/bin/sh
# nh-overlay-base — Magisk install hook.
#
# Magisk auto-overlays everything under $MODPATH/system/ via bind mount.
# This script just announces what we're installing and applies defensive
# permissions in case stale state from a previous install exists.

ui_print "*****************************************"
ui_print " NetHunter Overlay Base v1.0"
ui_print " Phone (1) (spacewar) / LOS 23.2 / Android 16"
ui_print "*****************************************"
ui_print "- Installs into /system/priv-app via overlay:"
ui_print "    NetHunter (com.offsec.nethunter)"
ui_print "    NetHunter Terminal (com.offsec.nhterm)"
ui_print "    F-Droid (org.fdroid.fdroid)"
ui_print "    F-Droid Privileged Extension (silent installs)"
ui_print "- Pre-configured F-Droid repos:"
ui_print "    NetHunter Store (store.nethunter.com)"
ui_print "    IzzyOnDroid (apt.izzysoft.de/fdroid)"
ui_print "- privapp-permissions XML grants INSTALL/DELETE_PACKAGES to F-Droid PrivExt"
ui_print "- addon.d hook for OTA survival"
ui_print "- Reboot required after install"

# Refuse install on incompatible Magisk versions
if [ "$MAGISK_VER_CODE" -lt 24000 ]; then
  abort "! Magisk 24+ required (you have $MAGISK_VER_CODE)"
fi

# If user previously installed F-Droid Privileged Extension as a regular app,
# Android refuses to grant it priv-app status due to signature mismatch.
# Warn — user must uninstall manually before rebooting.
if pm list packages 2>/dev/null | grep -q '^package:org.fdroid.fdroid.privileged$'; then
  if [ ! -d /system/priv-app/FDroidPrivilegedExtension ]; then
    ui_print " "
    ui_print "! WARNING: org.fdroid.fdroid.privileged is installed as user-app."
    ui_print "  Uninstall it before reboot or priv-app status will not activate:"
    ui_print "    su -c 'pm uninstall org.fdroid.fdroid.privileged'"
    ui_print " "
  fi
fi
if pm list packages 2>/dev/null | grep -q '^package:org.fdroid.fdroid$'; then
  if [ ! -d /system/priv-app/FDroid ]; then
    ui_print "! Note: org.fdroid.fdroid (user-app) will be replaced by the"
    ui_print "  /system/priv-app version. May want to backup repos/settings first."
  fi
fi

# Defensive permission set (Magisk's overlay applies these automatically but
# stale state from older installs may have wrong ones)
set_perm_recursive $MODPATH/system 0 0 0755 0644
set_perm_recursive $MODPATH/system/priv-app 0 0 0755 0644
set_perm $MODPATH/system/etc/permissions/privapp-permissions-nh-overlay-base.xml 0 0 0644 u:object_r:system_file:s0
set_perm $MODPATH/system/addon.d/80-nh-overlay-base.sh 0 0 0755 u:object_r:system_file:s0
