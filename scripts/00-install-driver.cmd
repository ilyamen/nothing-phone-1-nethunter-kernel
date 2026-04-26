@echo off
REM Manual binding helper for Nothing Phone 1 fastboot bootloader (VID_18D1&PID_D00D).
REM The Google USB Driver's android_winusb.inf doesn't list this PID, but the .cat
REM signature stays valid as long as we don't modify the .inf — we just point
REM Device Manager at it manually.
REM
REM Steps (with phone in fastboot mode, USB connected):
REM   1. Win+X → Device Manager
REM   2. Look for "Android" or unknown device under "Other devices"
REM   3. Right-click → Update driver
REM   4. Browse my computer for drivers
REM   5. Let me pick from a list of available drivers on my computer
REM   6. Have Disk → Browse → C:\Users\shidl\Downloads\google-usb-driver\usb_driver\android_winusb.inf
REM   7. Select "Android Bootloader Interface" → Next
REM   8. Confirm "Install this driver software anyway" if prompted

start ms-settings:device-manager
echo Driver files at: C:\Users\shidl\Downloads\google-usb-driver\usb_driver\android_winusb.inf
echo Choose: Android Bootloader Interface
pause
