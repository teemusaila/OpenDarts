#!/bin/sh
# This code was generated with AI (Claude by Anthropic). MIT License, see LICENSE and README.
# tailscale-install.sh (optional): reach the scoreboard from the internet with Tailscale Funnel.
#
# Run as root on the Pi (install.sh does this when INSTALL_TAILSCALE=yes). Settings from the environment:
#   TS_HOSTNAME       machine name (default autodarts-pi)
#   TS_AUTHKEY        optional auth key; without it the script prints a login link and waits
#   TS_FUNNEL_PUBLIC  yes: public read-only view at https://<name>.<tailnet>.ts.net/
#   TS_FUNNEL_PLAY    yes: full scoreboard with sign-in at /play/ (only if a scoreboard user exists)
#   TS_HTTPS_REDIRECT yes: send home-network visitors to the /play/ HTTPS address (needs TS_FUNNEL_PLAY)
# Login state is kept in /data/tailscale, so it survives reboots. Turn sharing off with:
#   tailscale funnel --https=443 off

set -e
HOST=${TS_HOSTNAME:-autodarts-pi}
PORT=${SCOREBOARD_PORT:-8080}
[ "$(id -u)" = 0 ] || { echo "Run as root."; exit 1; }
grep -q ' /data ' /proc/mounts || { echo "/data is not mounted."; exit 1; }

echo "== Installing Tailscale"
apk add -q tailscale tailscale-openrc
apk cache -q sync 2>/dev/null || true   # packages come back from this cache at boot
modprobe tun
grep -qx tun /etc/modules || echo tun >> /etc/modules
mkdir -p /data/tailscale && chmod 700 /data/tailscale
sed -i 's|^#\{0,1\}statedir=.*|statedir="/data/tailscale"|' /etc/conf.d/tailscale
grep -q '^statedir=' /etc/conf.d/tailscale || echo 'statedir="/data/tailscale"' >> /etc/conf.d/tailscale
rc-update add tailscale default >/dev/null
rc-service tailscale restart >/dev/null 2>&1 || rc-service tailscale start
lbu include /etc/conf.d/tailscale
lbu commit -d
sleep 2

echo "== Logging in"
if tailscale status >/dev/null 2>&1; then
  echo "Already logged in."
elif [ -n "$TS_AUTHKEY" ]; then
  tailscale up --accept-dns=false --hostname="$HOST" --authkey="$TS_AUTHKEY"
else
  echo "Open the link below and log in to your Tailscale account:"
  tailscale up --accept-dns=false --hostname="$HOST"
fi

echo "== Funnel"
if [ "$TS_FUNNEL_PUBLIC" = yes ]; then
  if rc-service scoreboard-public status >/dev/null 2>&1; then
    tailscale funnel --bg --https=443 http://127.0.0.1:8081
  else
    echo "Skipping the public view: install it first (INSTALL_PUBLIC_VIEW=yes)."
  fi
fi
if [ "$TS_FUNNEL_PLAY" = yes ]; then
  if grep -q '^/cgi-bin:' /data/scoreboard-auth/httpd.conf 2>/dev/null; then
    tailscale funnel --bg --https=443 --set-path /play "http://127.0.0.1:$PORT"
    NAME=$(tailscale status --json --peers=false 2>/dev/null | sed -n 's/.*"DNSName": *"\([^"]*\)\.".*/\1/p' | head -1)
    SET=/data/scoreboard/data/settings
    if [ "$TS_HTTPS_REDIRECT" = yes ] && [ -n "$NAME" ]; then
      { grep -v '^SECURE_URL=' "$SET" 2>/dev/null; echo "SECURE_URL=https://$NAME/play/"; } > /tmp/sb-set.$$
      cat /tmp/sb-set.$$ > "$SET"; rm -f /tmp/sb-set.$$; chown nobody "$SET"
      echo "Home-network visitors are now sent to https://$NAME/play/ (change it on the Settings page)."
    fi
  else
    echo "Skipping /play: add a scoreboard user first (scoreboard-user add NAME). Without users it would be open to anyone."
  fi
fi
# Routes the keep-alive check restores if they go missing (empty the file to stop sharing for good).
mkdir -p /data/scoreboard/data
tailscale funnel status 2>/dev/null | sed -n 's#^|-- \(/[^ ]*\) *proxy http://127\.0\.0\.1:\([0-9]*\)$#\1 \2#p' > /data/scoreboard/data/funnel-routes || true
tailscale funnel status || true
echo "If Tailscale printed a link to enable Funnel, open it, allow Funnel, and run this script again."
echo "A new name can take a few minutes to appear in DNS."
