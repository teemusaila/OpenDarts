#!/bin/sh
# This code was generated with AI (Claude by Anthropic). MIT License, see LICENSE and README.
# lights-install.sh: switch the dartboard lights (a Tuya/Nedis Wi-Fi plug) automatically.
#
# Run as root on the Pi:   sh lights-install.sh
#
# Needs /data/lights/config.json (device_id, ip, local_key, version, idle_minutes, api); the key is
# NOT part of this script. The service watches the board API (port 3180). Lights go on when the board
# starts or a dart is detected, and off after idle_minutes without any board activity.
# A second rule turns the lights off after no_score_minutes (default 15) without a new dart, even if
# other board events keep arriving.
# The scoreboard also touches /data/lights/ping when a game starts, which counts as activity.
# Force the lights by writing "on", "off" or "auto" into /data/lights/mode.
# Installs python3 (kept across reboots with lbu) and tinytuya in /data/lights/venv.

set -e
DIR=/data/lights
[ "$(id -u)" = 0 ] || { echo "Run as root."; exit 1; }
grep -q ' /data ' /proc/mounts || { echo "/data is not mounted."; exit 1; }
[ -f "$DIR/config.json" ] || { echo "Missing $DIR/config.json."; exit 1; }

echo "== Installing python3 and tinytuya"
apk add -q python3
# A diskless Pi reinstalls packages from the SD-card cache at boot: make sure it has all of them.
apk cache -q sync 2>/dev/null || true
[ -x "$DIR/venv/bin/python" ] || python3 -m venv "$DIR/venv"
"$DIR/venv/bin/pip" install -q tinytuya

echo "== Writing the controller"
cat > "$DIR/lights.py" <<'EOF_PY'
#!/usr/bin/env python3
"""Autodarts lights: plug on at board activity, off after idle_minutes without any."""
# This code was generated with AI (Claude by Anthropic). MIT License (Darts_Scoreboard_for_AutoDarts).
import json, os, sys, time, urllib.request, tinytuya

DIR = "/data/lights"
CONFIG = DIR + "/config.json"
PING = DIR + "/ping"
cfg, IDLE, NOSCORE, API, cfg_mtime = {}, 600.0, 900.0, "", None


def load():
    """Read config.json. Called at start and whenever the file changes (the scoreboard's Settings page)."""
    global cfg, IDLE, NOSCORE, API, cfg_mtime
    cfg_mtime = os.stat(CONFIG).st_mtime
    cfg = json.load(open(CONFIG))
    IDLE = float(cfg.get("idle_minutes", 10)) * 60
    NOSCORE = float(cfg.get("no_score_minutes", 15)) * 60
    API = cfg.get("api", "http://127.0.0.1:3180/api/state")


load()


def log(msg):
    print(time.strftime("%Y-%m-%d %H:%M:%S"), msg, flush=True)


def plug():
    d = tinytuya.OutletDevice(cfg["device_id"], cfg["ip"], cfg["local_key"], version=cfg.get("version", 3.3))
    d.set_socketTimeout(5)
    d.set_socketRetryLimit(1)
    return d


def is_on():
    try:
        return bool(plug().status().get("dps", {}).get("1"))
    except Exception as e:
        log("status failed: %s" % e)
        return None


def switch(want):
    for attempt in range(3):
        try:
            d = plug()
            (d.turn_on if want else d.turn_off)()
            time.sleep(0.5)
            if bool(d.status().get("dps", {}).get("1")) == want:
                log("lights %s" % ("ON" if want else "OFF"))
                return True
        except Exception as e:
            log("switch failed: %s" % e)
        time.sleep(2)
    return False


def board():
    try:
        with urllib.request.urlopen(API, timeout=3) as r:
            s = json.load(r)
        return (s.get("running"), s.get("status"), s.get("event"), s.get("numThrows"))
    except Exception:
        return None


def ping_time():
    try:
        return os.stat(PING).st_mtime
    except OSError:
        return None


def mode():
    try:
        m = open(DIR + "/mode").read().strip().lower()
        return m if m in ("on", "off") else "auto"
    except OSError:
        return "auto"


def main():
    last_state = board()
    last_activity = None   # None = no activity seen since start or since lights went off
    last_throw = None      # last new dart, or the moment the lights came on
    on = is_on()
    checked = time.time()
    log("started, idle %d min, no score %d min, lights %s, mode %s" % (IDLE // 60, NOSCORE // 60, {True: "on", False: "off", None: "unknown"}[on], mode()))
    if on:                 # lights were already on when we started: give them a full idle period
        last_activity = last_throw = time.time()
    last_nt = last_state[3] if last_state else None
    last_mode = mode()
    last_ping = ping_time()
    checked_cfg = time.time()
    while True:
        time.sleep(1)
        now = time.time()
        if now - checked_cfg > 5:
            checked_cfg = now
            try:
                if os.stat(CONFIG).st_mtime != cfg_mtime:
                    load()
                    on, checked = is_on(), now
                    log("settings reloaded: idle %d min, no score %d min, plug %s" % (IDLE // 60, NOSCORE // 60, cfg.get("ip")))
            except Exception as e:
                log("could not reload settings: %s" % e)
        m = mode()
        if m != last_mode:
            last_mode = m
            log("mode %s" % m)
            if m == "on" and switch(True): on = True; last_throw = now
            if m == "off" and switch(False): on = False
            if m == "auto":
                # Taking over again: what the board did while the mode was forced is not activity.
                last_state, last_ping = board(), ping_time()
                last_nt = last_state[3] if last_state else None
                if on: last_activity = last_throw = now
        if m != "auto":
            continue
        state = board()
        act = False
        if state is not None and state != last_state:
            last_state, act = state, True
            nt = state[3]
            if isinstance(nt, int) and isinstance(last_nt, int) and nt > last_nt:
                last_throw = now
            last_nt = nt
        pt = ping_time()
        if pt != last_ping:
            last_ping, act = pt, True
        if act:
            last_activity = now
            if on is not True or now - checked > 20:
                on = is_on()
                checked = now
            if on is False and switch(True):
                on = True
                last_throw = now
        quiet = last_activity is not None and now - last_activity > IDLE
        no_score = last_throw is not None and now - last_throw > NOSCORE
        if on and (quiet or no_score):
            log("%s, switching off" % ("no board activity" if quiet else "no new score"))
            if switch(False):
                on = False
                last_activity = last_throw = None
        if on is None and now - checked > 30:
            on, checked = is_on(), now


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
EOF_PY

echo "== Permissions"
[ -f "$DIR/mode" ] || echo auto > "$DIR/mode"
[ -f "$DIR/ping" ] || : > "$DIR/ping"
chown -R nobody "$DIR/config.json" "$DIR/mode" "$DIR/ping"
chmod 600 "$DIR/config.json"; chmod 666 "$DIR/mode" "$DIR/ping"
chmod 755 "$DIR" "$DIR/lights.py"

echo "== Creating the boot service"
cat > /etc/init.d/lights <<'EOF'
#!/sbin/openrc-run
name="lights"
description="Autodarts lights on a Tuya plug"
command="/data/lights/venv/bin/python"
command_args="/data/lights/lights.py"
command_user="nobody"
supervisor="supervise-daemon"
output_log="/data/logs/lights.log"
error_log="/data/logs/lights.log"
respawn_delay=5
respawn_max=0

depend() {
    need net localmount
    use autodarts
}

start_pre() {
    checkpath -d -m 0755 /data/logs
    checkpath -f -o nobody -m 0644 /data/logs/lights.log
}
EOF
chmod 755 /etc/init.d/lights
rc-update add lights default >/dev/null
lbu include /etc/init.d/lights

echo "== Saving and starting"
lbu commit -d
rc-service lights restart >/dev/null 2>&1 || rc-service lights start
sleep 4
tail -5 /data/logs/lights.log
echo
echo "Done. Force with: echo on > $DIR/mode   (or off, auto)"
