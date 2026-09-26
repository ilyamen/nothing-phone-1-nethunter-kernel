#!/system/bin/sh
# v1.1.0 passive test — NO DEAUTH, only listen
# Compares against v1.0.0 baseline: 18 beacon + 5 probe in 27s, ~42% drop ratio

WORKDIR=/data/local/tmp/v11-test
mkdir -p $WORKDIR && cd $WORKDIR

echo "============================================"
echo "STAGE 4 — sanity"
echo "============================================"
echo "kernel: $(uname -r)"
echo "wlan loaded: $(lsmod | grep -c '^wlan ')"

# Make sure WiFi is enabled (so wlan0 exists)
svc wifi enable
sleep 5

echo "wlan0: $(ip link show wlan0 2>&1 | head -1)"

echo ""
echo "--- enter monitor mode ---"
dmesg -c > /dev/null
ip link set wlan0 down 2>&1
echo 4 > /sys/module/wlan/parameters/con_mode
sleep 4
ip link set wlan0 up 2>&1
sleep 1
iw dev wlan0 info 2>&1 | grep -E "type|channel"

echo ""
echo "--- dmesg from monitor enter (look for FULL_MON / full_mon / dp_config) ---"
dmesg | grep -iE "full_mon|FULL_MON|dp_config|monitor|wlan|cnss|cld|DP" | tail -50

echo ""
echo "============================================"
echo "STAGE 5 — passive capture (27s, ch5)"
echo "============================================"
iw dev wlan0 set freq 2432 2>&1
sleep 1

RX_PKTS_BEFORE=$(cat /sys/class/net/wlan0/statistics/rx_packets)
RX_DROPS_BEFORE=$(cat /sys/class/net/wlan0/statistics/rx_dropped)
echo "rx_packets before: $RX_PKTS_BEFORE  rx_dropped before: $RX_DROPS_BEFORE"

echo ""
echo "--- 27s passive capture ---"
timeout 27 tcpdump -i wlan0 -w $WORKDIR/cap.pcap -U -s 0 > $WORKDIR/td.log 2>&1

RX_PKTS_AFTER=$(cat /sys/class/net/wlan0/statistics/rx_packets)
RX_DROPS_AFTER=$(cat /sys/class/net/wlan0/statistics/rx_dropped)
RX_PKTS_DELTA=$((RX_PKTS_AFTER - RX_PKTS_BEFORE))
RX_DROPS_DELTA=$((RX_DROPS_AFTER - RX_DROPS_BEFORE))

echo ""
echo "--- tcpdump stats ---"
cat $WORKDIR/td.log

echo ""
echo "--- pcap type breakdown ---"
tcpdump -nn -r $WORKDIR/cap.pcap 2>/dev/null | grep -oE "Beacon|Probe Request|Probe Response|Authentication|Association|Reassociation|Disassociation|Acknowledgment|Request-To-Send|Clear-To-Send|EAPOL|QoS Data|Data" | sort | uniq -c | sort -rn

echo ""
echo "============================================"
echo "VERDICT"
echo "============================================"
BEACONS=$(tcpdump -nn -r $WORKDIR/cap.pcap 2>/dev/null | grep -c "Beacon")
echo "Beacons captured (27s): $BEACONS    [v1.0.0 baseline: 18]"
echo "rx_packets delta:       $RX_PKTS_DELTA"
echo "rx_dropped delta:       $RX_DROPS_DELTA"
if [ $RX_PKTS_DELTA -gt 0 ]; then
  DROP_RATIO=$((RX_DROPS_DELTA * 100 / RX_PKTS_DELTA))
  echo "drop ratio:             $DROP_RATIO%       [v1.0.0 baseline: ~42%]"
fi

# Restore station mode at end
echo ""
echo "--- restoring STA mode ---"
ip link set wlan0 down
echo 0 > /sys/module/wlan/parameters/con_mode
sleep 2
ip link set wlan0 up
svc wifi enable

echo "--- DONE ---"
ls -la $WORKDIR/
