#!/bin/sh
# This code was generated with AI (Claude by Anthropic). MIT License, see LICENSE and README.
# keepalive-install.sh: keep the board and scoreboard healthy after reboots and hiccups.
#
# Run as root on the Pi:   sh keepalive-install.sh
#
# Installs:
#  - /usr/local/sbin/darts-keepalive, run at boot and every 5 minutes (cron). It
#      * starts or restarts the scoreboard, public view and lights if they stopped or don't answer,
#        and starts Autodarts if its service stopped;
#      * checks that every camera in the Autodarts config is on its USB port with its usual
#        /dev/video number; after a USB reconnect it re-attaches the cameras in order and restarts
#        Autodarts, so each camera matches its calibration again;
#      * restores the Tailscale Funnel routes in /data/scoreboard/data/funnel-routes
#        ("PATH PORT" per line; empty the file to stop sharing for good);
#      * once a day, checks that every package can be reinstalled from the SD-card cache at boot
#        (diskless Alpine) and refreshes the cache if not.
#  - /usr/local/sbin/cam-setup, run by mdev whenever a camera (re)appears: sets the fixed exposure
#    from /etc/conf.d/autodarts-camera (CAM_EXPOSURE=100 for example; empty = auto exposure).
# Logs: /data/logs/darts-keepalive.log and /data/logs/cameras.log (kept across reboots). Saved with lbu.

set -e
[ "$(id -u)" = 0 ] || { echo "Run as root."; exit 1; }
ROUTES=/data/scoreboard/data/funnel-routes
mkdir -p /data/logs

[ -f /etc/conf.d/autodarts-camera ] || cat > /etc/conf.d/autodarts-camera <<'EOF'
# Camera exposure applied whenever a camera appears (cam-setup), e.g. 100. Empty = auto exposure.
CAM_EXPOSURE=
EOF

cat > /usr/local/sbin/cam-setup <<'EOF'
#!/bin/sh
# cam-setup: called by mdev when a /dev/videoN node appears. Sets the fixed exposure on Autodarts
# cameras (UVC capture nodes), so a camera that reconnected doesn't fall back to auto exposure.
[ "$ACTION" = add ] || [ -z "$ACTION" ] || exit 0
DEV=${MDEV:-$1}
case "$DEV" in video[0-9]*) ;; *) exit 0 ;; esac
(
  sleep 2
  S=/sys/class/video4linux/$DEV
  [ "$(cat "$S/index" 2>/dev/null)" = 0 ] || exit 0
  case "$(readlink -f "$S/device/driver")" in */uvcvideo) ;; *) exit 0 ;; esac
  LOC=$(basename "$(readlink -f "$S/device")" | cut -d: -f1)
  . /etc/conf.d/autodarts-camera 2>/dev/null
  if [ -n "$CAM_EXPOSURE" ]; then
    v4l2-ctl -d "/dev/$DEV" -c auto_exposure=1 -c exposure_time_absolute="$CAM_EXPOSURE" 2>/dev/null
  fi
  echo "$(date '+%F %T') camera on USB $LOC is /dev/$DEV${CAM_EXPOSURE:+, exposure $CAM_EXPOSURE}" >> /data/logs/cameras.log
) </dev/null >/dev/null 2>&1 &
EOF
chmod 755 /usr/local/sbin/cam-setup
grep -q 'cam-setup' /etc/mdev.conf || sed -i '/^\$MODALIAS=/a video[0-9]+\troot:video 0660 @/usr/local/sbin/cam-setup' /etc/mdev.conf
grep -q 'cam-setup' /etc/mdev.conf || echo 'video[0-9]+	root:video 0660 @/usr/local/sbin/cam-setup' >> /etc/mdev.conf

cat > /usr/local/sbin/darts-keepalive <<'EOF'
#!/bin/sh
# darts-keepalive: services, cameras, Funnel routes and the boot package cache. See keepalive-install.sh.
LOG=/data/logs/darts-keepalive.log
ROUTES=/data/scoreboard/data/funnel-routes
ADCONF=/data/autodarts/.config/autodarts/config.toml
mkdir -p /data/logs
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }
answers() { wget -S -q -T 5 -O /dev/null "$1" 2>&1 | grep -qE 'HTTP/1.[01] (200|302|401)'; }
check() {   # service [url]
  [ -x "/etc/init.d/$1" ] || return 0
  if ! rc-service "$1" status >/dev/null 2>&1; then
    rc-service "$1" start >/dev/null 2>&1; log "$1 was stopped: started"; return 0
  fi
  [ -n "$2" ] || return 0
  if ! answers "$2"; then
    sleep 5; answers "$2" && return 0
    rc-service "$1" restart >/dev/null 2>&1; log "$1 did not answer: restarted"
  fi
}

# --- cameras: each configured camera on its USB port with its configured /dev/video number
cameras() {
  [ -f "$ADCONF" ] || return 0
  grep -o "native=/dev/video[0-9]*&[^']*location=[0-9.-]*" "$ADCONF" | sed 's#native=/dev/\(video[0-9]*\)&.*location=\(.*\)#\1 \2#' > /tmp/darts-cams
  [ -s /tmp/darts-cams ] || return 0
  missing= moved=
  while read -r dev loc; do
    if [ ! -e "/sys/bus/usb/devices/$loc" ]; then missing="$missing $loc"
    elif [ ! -e "/sys/bus/usb/devices/$loc:1.0/video4linux/$dev" ]; then moved="$moved $loc"; fi
  done < /tmp/darts-cams
  if [ -n "$missing" ]; then
    # Logged once per change, not every 5 minutes.
    [ "$(cat /tmp/darts-cams-missing 2>/dev/null)" = "$missing" ] || log "camera missing on USB$missing (check cable/power)"
    echo "$missing" > /tmp/darts-cams-missing; return 0
  fi
  [ -f /tmp/darts-cams-missing ] && { log "all cameras present again"; rm -f /tmp/darts-cams-missing; }
  [ -n "$moved" ] || return 0
  # A camera reconnected and got another /dev/video number: re-attach all cameras in config order so
  # they get their usual numbers back (lowest free), then restart Autodarts. At most once an hour.
  last=$(cat /tmp/darts-cams-rebind 2>/dev/null || echo 0)
  [ $(( $(date +%s) - last )) -gt 3600 ] || return 0
  date +%s > /tmp/darts-cams-rebind
  log "camera numbering changed on USB$moved: re-attaching cameras and restarting Autodarts"
  rc-service autodarts stop >/dev/null 2>&1; sleep 2
  while read -r dev loc; do for i in 0 1; do echo "$loc:1.$i" > /sys/bus/usb/drivers/uvcvideo/unbind 2>/dev/null; done; done < /tmp/darts-cams
  sleep 1
  while read -r dev loc; do for i in 0 1; do echo "$loc:1.$i" > /sys/bus/usb/drivers/uvcvideo/bind 2>/dev/null; done; sleep 1; done < /tmp/darts-cams
  sleep 3
  rc-service autodarts start >/dev/null 2>&1
  bad=; while read -r dev loc; do [ -e "/sys/bus/usb/devices/$loc:1.0/video4linux/$dev" ] || bad="$bad $loc"; done < /tmp/darts-cams
  [ -z "$bad" ] && log "cameras back on their usual numbers" || log "cameras still renumbered on USB$bad; a reboot will fix the order"
}

# --- packages: a diskless Pi reinstalls packages from the SD-card cache at every boot
packages() {
  last=$(cat /tmp/darts-apkcheck 2>/dev/null || echo 0)
  [ $(( $(date +%s) - last )) -gt 86400 ] || return 0
  date +%s > /tmp/darts-apkcheck
  [ -d /etc/apk/cache ] || return 0
  apk add --simulate --no-network $(cat /etc/apk/world) >/dev/null 2>&1 && return 0
  if apk cache -q sync >/dev/null 2>&1 && apk add --simulate --no-network $(cat /etc/apk/world) >/dev/null 2>&1; then
    log "package cache was incomplete: refreshed"
  else
    log "package cache is incomplete and could not be refreshed (no internet?); packages may be missing after a reboot"
  fi
}

check autodarts
cameras
check scoreboard "http://127.0.0.1:8080/?local"
check scoreboard-public "http://127.0.0.1:8081/"
check lights
packages

# --- Funnel routes, only when Tailscale runs and is logged in
[ -s "$ROUTES" ] || exit 0
command -v tailscale >/dev/null 2>&1 || exit 0
rc-service tailscale status >/dev/null 2>&1 || { rc-service tailscale start >/dev/null 2>&1; log "tailscale was stopped: started"; sleep 10; }
tailscale status >/dev/null 2>&1 || exit 0
st=$(tailscale funnel status 2>/dev/null)
while read -r path port; do
  case "$path:$port" in /*:[0-9]*) ;; *) continue ;; esac
  echo "$st" | grep -qE "^\|-- $path +proxy http://127\.0\.0\.1:$port\$" && continue
  if [ "$path" = / ]; then
    tailscale funnel --bg --https=443 "http://127.0.0.1:$port" >/dev/null 2>&1
  else
    tailscale funnel --bg --https=443 --set-path "$path" "http://127.0.0.1:$port" >/dev/null 2>&1
  fi && log "funnel route $path restored"
done < "$ROUTES"
exit 0
EOF
chmod 755 /usr/local/sbin/darts-keepalive

# Every 5 minutes (cron) and once at boot after the network and Tailscale had a minute.
rm -f /etc/periodic/15min/darts-keepalive
grep -q darts-keepalive /etc/crontabs/root || echo '*/5	*	*	*	*	/usr/local/sbin/darts-keepalive' >> /etc/crontabs/root
cat > /etc/local.d/darts-keepalive.start <<'EOF'
#!/bin/sh
( sleep 60; /usr/local/sbin/darts-keepalive ) >/dev/null 2>&1 &
EOF
chmod 755 /etc/local.d/darts-keepalive.start

if [ ! -f "$ROUTES" ] && command -v tailscale >/dev/null 2>&1; then
  mkdir -p "$(dirname "$ROUTES")"
  tailscale funnel status 2>/dev/null | sed -n 's#^|-- \(/[^ ]*\) *proxy http://127\.0\.0\.1:\([0-9]*\)$#\1 \2#p' > "$ROUTES" || true
fi
echo "Funnel routes kept alive ($ROUTES):"; cat "$ROUTES" 2>/dev/null; [ -s "$ROUTES" ] || echo "  (none)"

rc-update add crond default >/dev/null 2>&1
rc-update add local default >/dev/null 2>&1
rc-service crond restart >/dev/null 2>&1 || true
lbu include /usr/local/sbin/darts-keepalive /usr/local/sbin/cam-setup /etc/local.d/darts-keepalive.start \
            /etc/conf.d/autodarts-camera /etc/mdev.conf /etc/crontabs/root
lbu exclude /etc/periodic/15min/darts-keepalive >/dev/null 2>&1 || true
lbu commit -d
/usr/local/sbin/darts-keepalive
echo "Done. Logs: /data/logs/darts-keepalive.log, /data/logs/cameras.log"
