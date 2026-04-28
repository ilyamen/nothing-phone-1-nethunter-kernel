#!/sbin/sh
#
# ADDOND_VERSION=2
#
# /system/addon.d/80-nh-overlay-base.sh
# LineageOS addon.d hook: backs up overlay files before LOS OTA wipes /system,
# restores them after. /data files (incl. Magisk module) are not touched by OTA.
#
# This is a safety net for users who do A→B OTA where slot B was never seen
# Magisk. On normal Magisk-rooted boots the overlay re-applies regardless.

. /tmp/backuptool.functions

list_files() {
cat <<EOF
priv-app/NetHunter/NetHunter.apk
priv-app/NetHunterTerminal/NetHunterTerminal.apk
priv-app/FDroid/FDroid.apk
priv-app/FDroidPrivilegedExtension/FDroidPrivilegedExtension.apk
etc/permissions/privapp-permissions-nh-overlay-base.xml
etc/org.fdroid.fdroid/additional_repos.xml
EOF
}

case "$1" in
  backup)
    list_files | while read FILE DUMMY; do
      backup_file $S/"$FILE"
    done
  ;;
  restore)
    list_files | while read FILE REPLACEMENT; do
      R=""
      [ -n "$REPLACEMENT" ] && R="$S/$REPLACEMENT"
      [ -f "$C/$S/$FILE" ] && restore_file $S/"$FILE" "$R"
    done
  ;;
  pre-backup|post-backup|pre-restore|post-restore)
    # No-op
  ;;
esac
