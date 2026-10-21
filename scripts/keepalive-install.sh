#!/bin/sh
# This code was generated with AI (Claude by Anthropic). MIT License, see LICENSE and README.
# keepalive-install.sh: keep the scoreboard reachable after reboots and hiccups.
#
# Run as root on the Pi:   sh keepalive-install.sh
#
# Installs /usr/local/sbin/darts-keepalive, run at boot and every 15 minutes. It
#  - starts or restarts the scoreboard, its public view and the lights service if they've stopped
#    or don't answer, and starts Autodarts if its service has stopped;
#  - restores the Tailscale Funnel routes listed in /data/scoreboard/data/funnel-routes
#    (one "PATH PORT" per line, e.g. "/ 8081" and "/play 8080"). Empty the file to stop sharing,
#    otherwise the routes come back.
# Log: /var/log/darts-keepalive.log. Saved with lbu.

set -e
[ "$(id -u)" = 0 ] || { echo "Run as root."; exit 1; }
ROUTES=/data/scoreboard/data/funnel-routes

cat > /usr/local/sbin/darts-keepalive <<'EOF'
#!/bin/sh
# darts-keepalive: restart stopped services and restore Tailscale Funnel routes. See keepalive-install.sh.
LOG=/var/log/darts-keepalive.log
ROUTES=/data/scoreboard/data/funnel-routes
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }
answers() { wget -S -q -T 5 -O /dev/null "$1" 2>&1 | grep -qE 'HTTP/1.[01] (200|302|401)'; }
check() {   # service [url]
  [ -x "/etc/init.d/$1" ] || return 0
  if ! rc-service "$1" status >/dev/null 2>&1; then
    rc-service "$1" start >/dev/null 2>&1; log "$1 was stopped: started"; return 0
  fi
  [ -n "$2" ] || return 0
  if ! answers "$2"; then
    sleep 5; answers "$2" && return 0          # one retry before restarting
    rc-service "$1" restart >/dev/null 2>&1; log "$1 did not answer: restarted"
  fi
}
check autodarts
check scoreboard "http://127.0.0.1:8080/?local"
check scoreboard-public "http://127.0.0.1:8081/"
check lights

# Funnel routes, only when Tailscale runs and is logged in.
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

cat > /etc/periodic/15min/darts-keepalive <<'EOF'
#!/bin/sh
exec /usr/local/sbin/darts-keepalive
EOF
chmod 755 /etc/periodic/15min/darts-keepalive

# At boot: once the network and Tailscale had a minute to come up.
cat > /etc/local.d/darts-keepalive.start <<'EOF'
#!/bin/sh
( sleep 60; /usr/local/sbin/darts-keepalive ) >/dev/null 2>&1 &
EOF
chmod 755 /etc/local.d/darts-keepalive.start

# Routes to keep: the ones Funnel serves right now, unless a list exists already.
if [ ! -f "$ROUTES" ]; then
  mkdir -p "$(dirname "$ROUTES")"
  tailscale funnel status 2>/dev/null | sed -n 's#^|-- \(/[^ ]*\) *proxy http://127\.0\.0\.1:\([0-9]*\)$#\1 \2#p' > "$ROUTES" || true
fi
echo "Funnel routes kept alive ($ROUTES):"; cat "$ROUTES" 2>/dev/null; [ -s "$ROUTES" ] || echo "  (none)"

rc-update add crond default >/dev/null 2>&1
rc-update add local default >/dev/null 2>&1
lbu include /usr/local/sbin/darts-keepalive /etc/periodic/15min/darts-keepalive /etc/local.d/darts-keepalive.start
lbu commit -d
/usr/local/sbin/darts-keepalive
echo "Done. Log: /var/log/darts-keepalive.log"
