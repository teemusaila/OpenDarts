#!/bin/sh
# This code was generated with AI (Claude by Anthropic). MIT License, see LICENSE and README.
# public-view-install.sh: a read-only public copy of the scoreboard for sharing with friends.
#
# Run as root on the Pi, after scoreboard-install.sh:   sh public-view-install.sh
#
# Serves /data/scoreboard-public on 127.0.0.1:8081 (not reachable from the network by itself; put a
# tunnel or Funnel in front of it). It shows only the passive display (board, hits, last 10 scores)
# of the game running on the scoring device. It has no controls and no write endpoints: there is no
# players list, no lights and no way to post a game. Re-run after every scoreboard update.

set -e
SRC=/data/scoreboard/index.html
DIR=/data/scoreboard-public
PORT=8081

[ "$(id -u)" = 0 ] || { echo "Run as root."; exit 1; }
[ -f "$SRC" ] || { echo "Install the scoreboard first (scoreboard-install.sh)."; exit 1; }
HTTPD=$(command -v httpd) || { echo "httpd not found."; exit 1; }

echo "== Writing the read-only copy to $DIR"
mkdir -p "$DIR/cgi-bin"
sed "s|<script>|<script>window.PUBLIC_VIEW = true;</script>\n<script>|" "$SRC" > "$DIR/index.html"
grep -q 'window.PUBLIC_VIEW = true' "$DIR/index.html" || { echo "Could not mark the public copy."; exit 1; }
cat > "$DIR/cgi-bin/game" <<'EOF_GAME'
#!/bin/sh
# Read-only: returns the live game published by the scoring device. Ignores anything sent to it.
printf 'Content-Type: application/json\r\nCache-Control: no-store\r\n\r\n'
F=/tmp/scoreboard-game.json
if [ -f "$F" ]; then cat "$F"; else echo '{"none":true}'; fi
EOF_GAME
chmod 755 "$DIR" "$DIR/cgi-bin" "$DIR/cgi-bin/game"; chmod 644 "$DIR/index.html"

echo "== Creating the boot service"
cat > /etc/init.d/scoreboard-public <<EOF
#!/sbin/openrc-run
name="scoreboard-public"
description="Read-only public scoreboard copy on 127.0.0.1:$PORT"
command="$HTTPD"
command_args="-f -p 127.0.0.1:$PORT -h $DIR"
command_user="nobody"
supervisor="supervise-daemon"
respawn_delay=5
respawn_max=0

depend() {
    need net localmount
}
EOF
chmod 755 /etc/init.d/scoreboard-public
rc-update add scoreboard-public default >/dev/null
lbu include /etc/init.d/scoreboard-public

echo "== Saving and starting"
lbu commit -d
rc-service scoreboard-public restart >/dev/null 2>&1 || rc-service scoreboard-public start
sleep 1
if wget -qO /dev/null "http://127.0.0.1:$PORT/"; then echo "Done. Public copy listening on 127.0.0.1:$PORT"; else echo "Public copy did not answer."; exit 1; fi
