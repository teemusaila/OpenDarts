#!/bin/sh
# This code was generated with AI (Claude by Anthropic). MIT License, see LICENSE and README.
# calibrate-install.sh: calibrate the Autodarts cameras at every boot, with the board lights on.
#
# Run as root:   sh calibrate-install.sh
#
# Installs /usr/local/sbin/darts-calibrate and a boot hook (/etc/local.d/darts-calibrate.start).
# After boot the script waits for Autodarts, starts the board, then:
#   1. switches the lights on and waits 5 seconds,
#   2. runs Autodarts' own auto-calibration (POST /api/config/calibration/auto), which stores the
#      result in calibration.json on /data, so it survives reboots,
#   3. checks that all cameras are calibrated, stops the board and switches the lights off.
# A copy of the calibration from before the run is kept (calibration.json.before); if the new
# calibration fails, it is put back. The lights go back to the mode they had (usually auto).
# Auto-calibration needs the internet (Autodarts' servers). Without it the old calibration stays.
# Log: /data/logs/calibrate.log.  Run by hand: darts-calibrate.  Turn off at boot:
#   echo off > /data/autodarts/boot-calibration      (echo on > ... turns it back on)
# Re-running this installer is safe.

set -e
[ "$(id -u)" = 0 ] || { echo "Run as root."; exit 1; }
grep -q ' /data ' /proc/mounts || { echo "/data is not mounted."; exit 1; }

echo "== Writing darts-calibrate"
cat > /usr/local/sbin/darts-calibrate <<'EOF'
#!/bin/sh
# darts-calibrate: lights on, wait 5 s, auto-calibrate the cameras, lights off. See calibrate-install.sh.
API=http://127.0.0.1:3180
LOG=/data/logs/calibrate.log
CAL=/data/autodarts/.config/autodarts/calibration.json
SWITCH=/data/autodarts/boot-calibration
MODE=/data/lights/mode
CAMS=3
LOCKDIR=/tmp/darts-calibrate.lock

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }
[ "$1" = --boot ] && [ "$(cat "$SWITCH" 2>/dev/null)" = off ] && exit 0
mkdir "$LOCKDIR" 2>/dev/null || { echo "Already running."; exit 0; }

prev=
lights() { [ -w "$MODE" ] && echo "$1" > "$MODE"; }
cleanup() {
  [ -n "$prev" ] && lights "$prev"      # never leave the lights forced on or off
  rmdir "$LOCKDIR" 2>/dev/null
}
trap cleanup EXIT

state()    { wget -qO- -T 3 "$API/api/state" 2>/dev/null; }
geometry() { wget -qO- -T 3 "$API/api/config/calibration/geometry" 2>/dev/null; }
calibrated() { geometry | grep -q '"calibrated":true' && [ "$(geometry | sed -n 's/.*"num_cams":\([0-9]*\).*/\1/p')" = "$CAMS" ]; }
put() { printf 'PUT %s HTTP/1.0\r\nHost: 127.0.0.1\r\nContent-Length: 0\r\n\r\n' "$1" | nc -w 5 127.0.0.1 3180 >/dev/null 2>&1; }
wait_for() {   # wait_for SECONDS COMMAND...
  n=$1; shift
  while [ "$n" -gt 0 ]; do "$@" && return 0; sleep 2; n=$((n - 2)); done
  return 1
}
running() { state | grep -q '"running":true'; }
stopped() { state | grep -q '"running":false'; }

log "== boot calibration"
wait_for 300 state >/dev/null || { log "Autodarts did not answer, giving up"; exit 1; }

# The board must run, with all cameras up, before it can calibrate.
n=0
while ! running && [ $n -lt 60 ]; do put /api/start; sleep 3; n=$((n + 1)); done
running || { log "board did not start, giving up"; exit 1; }
wait_for 120 calibrated || { log "cameras not calibrated after start (need $CAMS), trying anyway"; }

[ -r "$MODE" ] && prev=$(cat "$MODE")
log "lights on (mode was ${prev:-none})"
lights on
sleep 5

cp -p "$CAL" "$CAL.before" 2>/dev/null
before=$(date -r "$CAL" +%s 2>/dev/null)
log "calibrating"
if wget -qO- -T 240 --post-data= "$API/api/config/calibration/auto" >/dev/null 2>&1 && calibrated; then
  after=$(date -r "$CAL" +%s 2>/dev/null)
  if [ "$after" != "$before" ]; then log "calibration OK, saved to $CAL"; else log "calibration OK (file unchanged)"; fi
  cp -p "$CAL" "$CAL.lastgood" 2>/dev/null
else
  log "calibration FAILED"
  if [ -f "$CAL.before" ] && ! calibrated; then
    cat "$CAL.before" > "$CAL" && log "old calibration put back, restarting Autodarts" && rc-service autodarts restart >/dev/null 2>&1
  fi
fi

# Leave the board stopped, as it is after boot until a game starts, so the lights controller
# does not see the shutdown as player activity when it takes over again.
put /api/stop
wait_for 30 stopped || log "board still running"
log "lights off"
lights off
sleep 6                                  # the lights service switches the plug within a few seconds
log "done"
EOF
chmod 755 /usr/local/sbin/darts-calibrate

cat > /etc/local.d/darts-calibrate.start <<'EOF'
#!/bin/sh
( sleep 45; /usr/local/sbin/darts-calibrate --boot ) >/dev/null 2>&1 &
EOF
chmod 755 /etc/local.d/darts-calibrate.start
[ -f /data/autodarts/boot-calibration ] || echo on > /data/autodarts/boot-calibration

rc-update add local default >/dev/null 2>&1
lbu include /usr/local/sbin/darts-calibrate /etc/local.d/darts-calibrate.start
lbu commit -d
echo "Done. Calibration runs 45 s after every boot (log: /data/logs/calibrate.log)."
echo "Try it now: darts-calibrate     Turn off at boot: echo off > /data/autodarts/boot-calibration"
