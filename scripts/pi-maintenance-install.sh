#!/bin/sh
# This code was generated with AI (Claude by Anthropic). MIT License, see LICENSE and README.
# pi-maintenance-install.sh: weekly backup, daily log trim and hardware watchdog for the Autodarts Pi.
#
# Run as root on the Pi:   sh pi-maintenance-install.sh
# Everything is saved with lbu, so it survives reboots. Re-running is safe.

set -e
[ "$(id -u)" = 0 ] || { echo "Run as root."; exit 1; }

cat > /usr/local/sbin/pi-backup <<'EOF'
#!/bin/sh
# pi-backup: archive the Autodarts install, the scoreboard (incl. player list) and the boot
# settings to /data/backups. Keeps the newest 5. Copy the files off the card for real safety:
#   scp root@<pi-address>:/data/backups/pi-backup-*.tar.gz .
D=/data/backups
mkdir -p "$D"; chmod 700 "$D"
F="$D/pi-backup-$(date +%Y%m%d-%H%M).tar.gz"
tar czf "$F" -C / data/autodarts data/scoreboard \
  media/mmcblk0p1/config.txt media/mmcblk0p1/cmdline.txt $(cd / && ls media/mmcblk0p1/*.apkovl.tar.gz) 2>/dev/null || [ $? -eq 1 ]
(cd "$D" && sha256sum "$(basename "$F")" > "$F.sha256")
ls -1t "$D"/pi-backup-*.tar.gz 2>/dev/null | tail -n +6 | while read -r old; do rm -f "$old" "$old.sha256"; done
echo "$F"
EOF

cat > /etc/periodic/weekly/pi-backup <<'EOF'
#!/bin/sh
exec /usr/local/sbin/pi-backup >/dev/null 2>&1
EOF

cat > /etc/periodic/daily/trim-logs <<'EOF'
#!/bin/sh
# Keep the in-RAM Autodarts log from growing without limit (the daemon writes in append mode).
L=/var/log/autodarts.log
if [ -f "$L" ] && [ "$(wc -c < "$L")" -gt 5242880 ]; then
  tail -c 1048576 "$L" > "$L.1" && : > "$L"
fi
EOF

# Hardware watchdog: reboots the Pi if it hangs for 30 s. Closed cleanly on shutdown.
cat > /etc/local.d/watchdog.start <<'EOF'
#!/bin/sh
pgrep -x watchdog >/dev/null || watchdog -t 5 -T 30 /dev/watchdog
EOF
cat > /etc/local.d/watchdog.stop <<'EOF'
#!/bin/sh
pkill -x watchdog
EOF

chmod 755 /usr/local/sbin/pi-backup /etc/periodic/weekly/pi-backup /etc/periodic/daily/trim-logs \
          /etc/local.d/watchdog.start /etc/local.d/watchdog.stop
lbu include /usr/local/sbin/pi-backup /etc/periodic/weekly/pi-backup /etc/periodic/daily/trim-logs \
            /etc/local.d/watchdog.start /etc/local.d/watchdog.stop

/etc/local.d/watchdog.start
echo "Watchdog running: $(pgrep -x watchdog)"
/usr/local/sbin/pi-backup
lbu commit -d
echo "Done."
