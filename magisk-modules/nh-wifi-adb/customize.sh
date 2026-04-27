#!/system/bin/sh
# Run during Magisk module install. Just announce ourselves.
ui_print "- NetHunter WiFi ADB"
ui_print "- Auto-starts adbd on TCP 44444 every boot"
ui_print "- Connect from PC: adb connect <phone-ip>:44444"
ui_print "- Reboot required after install"
set_perm $MODPATH/service.sh 0 0 0755
