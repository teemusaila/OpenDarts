#!/bin/sh
# This code was generated with AI (Claude by Anthropic). MIT License, see LICENSE and README.
# install.sh: install Autodarts and Darts Scoreboard on a Raspberry Pi running Alpine Linux.
#
# Run as root on the Pi, in this folder:   sh install.sh
# (or from your computer: ./deploy.sh, which copies everything over and runs this)
#
# Reads config.env. Re-running is safe: it updates everything and keeps players, users and settings.

set -e
cd "$(dirname "$0")"
[ "$(id -u)" = 0 ] || { echo "Run as root."; exit 1; }
[ -f config.env ] || { echo "Copy config.env.example to config.env and fill it in first."; exit 1; }
. ./config.env
export SCOREBOARD_PORT TS_HOSTNAME TS_AUTHKEY TS_FUNNEL_PUBLIC TS_FUNNEL_PLAY TS_HTTPS_REDIRECT
export AD_VERSION AD_REINSTALL OPT_CLOCK_SYNC OPT_CPU_PERFORMANCE OPT_WIFI_POWERSAVE_OFF OPT_CAMERA_EXPOSURE \
       OPT_DISABLE_BLUETOOTH OPT_FAST_BOOT OPT_OVERCLOCK OPT_STATUS_LOGIN
on() { [ "$1" = yes ]; }

if on "$INSTALL_AUTODARTS"; then
  echo "##### Autodarts board"
  sh scripts/autodarts-install.sh
fi

echo "##### Scoreboard"
sh scripts/scoreboard-install.sh

if [ -n "$SCOREBOARD_ADMIN_USER" ] && ! grep -q '^/cgi-bin:' /data/scoreboard-auth/httpd.conf; then
  echo "##### First user: $SCOREBOARD_ADMIN_USER"
  if [ -n "$SCOREBOARD_ADMIN_PASSWORD" ]; then
    printf '%s\n%s\n' "$SCOREBOARD_ADMIN_PASSWORD" "$SCOREBOARD_ADMIN_PASSWORD" | scoreboard-user add "$SCOREBOARD_ADMIN_USER"
  else
    scoreboard-user add "$SCOREBOARD_ADMIN_USER"
  fi
fi

if on "$INSTALL_PUBLIC_VIEW"; then
  echo "##### Public read-only view"
  sh scripts/public-view-install.sh
fi

if on "$INSTALL_LIGHTS"; then
  echo "##### Lights"
  if [ -z "$LIGHTS_DEVICE_ID" ] || [ -z "$LIGHTS_IP" ] || [ -z "$LIGHTS_LOCAL_KEY" ]; then
    echo "INSTALL_LIGHTS=yes needs LIGHTS_DEVICE_ID, LIGHTS_IP and LIGHTS_LOCAL_KEY in config.env."; exit 1
  fi
  mkdir -p /data/lights
  j() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }   # escape for JSON
  ( umask 077; cat > /data/lights/config.json <<EOF_JSON
{
  "device_id": "$(j "$LIGHTS_DEVICE_ID")",
  "ip": "$(j "$LIGHTS_IP")",
  "local_key": "$(j "$LIGHTS_LOCAL_KEY")",
  "version": ${LIGHTS_VERSION:-3.3},
  "idle_minutes": ${LIGHTS_IDLE_MINUTES:-10},
  "no_score_minutes": ${LIGHTS_NO_SCORE_MINUTES:-15},
  "api": "http://127.0.0.1:3180/api/state"
}
EOF_JSON
  )
  sh scripts/lights-install.sh
fi

if on "$INSTALL_MAINTENANCE"; then
  echo "##### Backup, log trim and watchdog"
  sh scripts/pi-maintenance-install.sh
fi

if on "$INSTALL_TAILSCALE"; then
  echo "##### Tailscale"
  sh scripts/tailscale-install.sh
fi

if on "$INSTALL_KEEPALIVE"; then
  echo "##### Keep-alive check"
  sh scripts/keepalive-install.sh
fi

echo
echo "All done."
grep -q '^/cgi-bin:' /data/scoreboard-auth/httpd.conf || echo "Sign-in is off. Add a user to turn it on:  scoreboard-user add NAME"
