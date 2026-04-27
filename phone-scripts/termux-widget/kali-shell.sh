#!/data/data/com.termux/files/usr/bin/bash
# Open a shell in the Kali NetHunter chroot with proper PATH set up.

echo "==> entering Kali chroot..."
su -c "chroot /data/local/nhsystem/kali-arm64 /bin/bash --login -c '
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
  export TERM=xterm-256color
  /bin/bash --login
'"
