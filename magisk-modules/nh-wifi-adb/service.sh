#!/system/bin/sh
# nh-wifi-adb: enable adbd on TCP port 44444 after Android is up.
# Runs in Magisk's late_start service trigger (after Zygote, before user unlock).
# Survives every reboot as long as the module is enabled in Magisk Manager.

PORT=44444
LOG=/cache/nh-wifi-adb.log

mkdir -p /cache 2>/dev/null

{
  echo "=== $(date) nh-wifi-adb service.sh ==="

  # Wait for boot to complete — adbd is restarted at various stages
  i=0
  until [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ] || [ $i -gt 30 ]; do
    sleep 2
    i=$((i + 1))
  done
  echo "boot_completed reached after ${i} polls"

  # Extra cushion so init has finished restarting adbd for any Wireless-Debugging toggle
  sleep 5

  # Set property + restart adbd to pick up the TCP port
  setprop service.adb.tcp.port "$PORT"
  stop adbd
  start adbd

  echo "[+] adbd restarted on TCP port $PORT"
  netstat -ntlp 2>/dev/null | grep ":$PORT " | head -2
  echo
} >> "$LOG" 2>&1
