#!/bin/sh
# This code was generated with AI (Claude by Anthropic). MIT License, see LICENSE and README.
# autodarts-install.sh: install the Autodarts board service on Alpine Linux (Raspberry Pi 4 or 5),
# with optional optimizations.
#
# Run as root on the Pi, from the scripts folder (install.sh does this when INSTALL_AUTODARTS=yes).
#
# Autodarts itself is downloaded from its official installer (autodarts.sh) as the user
# "autodarts", home /data/autodarts. The official build needs glibc; Alpine uses musl, so it runs
# through gcompat plus a small shim (adshim.c) that adds the two glibc functions gcompat lacks.
# Nothing account-related is set up here: pair the board with your Autodarts account afterwards
# with the "ad" command on the Pi (or "autodarts remote" from another computer).
#
# Settings from the environment (config.env):
#   AD_VERSION              empty = latest; or a version such as 2.0.2
#   AD_REINSTALL            yes = download again even if Autodarts is installed (update)
#   OPT_CLOCK_SYNC          yes = set the clock from the network before Autodarts starts
#   OPT_CPU_PERFORMANCE     yes = CPU governor "performance" (steady frame rate)
#   OPT_WIFI_POWERSAVE_OFF  yes = no Wi-Fi power saving (lower, steadier latency)
#   OPT_CAMERA_EXPOSURE     empty = cameras on auto exposure; a number = fixed exposure time
#   OPT_DISABLE_BLUETOOTH   yes = turn Bluetooth off (frees the UART, less interference)
#   OPT_FAST_BOOT           yes = start services in parallel
#   OPT_OVERCLOCK           empty = stock clock; Pi 4: 2000; Pi 5: 2600, 2800 or 3000 (MHz)
#   OPT_STATUS_LOGIN        yes = board status when you log in, and the "ad" command

set -e
cd "$(dirname "$0")"
HOME_DIR=/data/autodarts
on() { [ "$1" = yes ]; }

[ "$(id -u)" = 0 ] || { echo "Run as root."; exit 1; }
[ -f /etc/alpine-release ] || { echo "This is for Alpine Linux."; exit 1; }
[ "$(uname -m)" = aarch64 ] || { echo "Needs 64-bit Alpine (aarch64); this is $(uname -m)."; exit 1; }
grep -q ' /data ' /proc/mounts || { echo "/data is not mounted (see README: Preparing the Pi)."; exit 1; }
MODEL=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo unknown)
case "$MODEL" in
  *"Raspberry Pi 5"*) PI=5 ;;
  *"Raspberry Pi 4"*|*"Raspberry Pi 400"*) PI=4 ;;
  *) PI=; echo "Note: $MODEL is not a Raspberry Pi 4 or 5. Continuing; overclocking is skipped." ;;
esac
LBU_MEDIA=$(sed -n 's/^LBU_MEDIA=//p' /etc/lbu/lbu.conf 2>/dev/null)
BOOT=/media/${LBU_MEDIA:-mmcblk0p1}

echo "== Packages"
apk add -q gcompat libgcc libstdc++ v4l-utils ca-certificates bash curl
on "$OPT_CLOCK_SYNC" && apk add -q chrony
# A diskless Pi reinstalls packages from the SD-card cache at boot: make sure it has all of them.
apk cache -q sync 2>/dev/null || true
grep -qx uvcvideo /etc/modules || echo uvcvideo >> /etc/modules
modprobe uvcvideo 2>/dev/null || true

echo "== User autodarts"
grep -q '^autodarts:' /etc/group || addgroup -g 1000 autodarts 2>/dev/null || addgroup autodarts
id autodarts >/dev/null 2>&1 || adduser -D -h "$HOME_DIR" -s /bin/sh -G autodarts autodarts
addgroup autodarts video >/dev/null 2>&1 || true
mkdir -p "$HOME_DIR"; chown autodarts:autodarts "$HOME_DIR"

echo "== glibc shim"
apk add -q --virtual .adshim-build gcc musl-dev
cp adshim.c "$HOME_DIR/adshim.c"
gcc -O2 -shared -fPIC -o "$HOME_DIR/adshim.so" "$HOME_DIR/adshim.c"
apk del -q .adshim-build
chown root:autodarts "$HOME_DIR/adshim.c" "$HOME_DIR/adshim.so"; chmod 644 "$HOME_DIR/adshim.c"; chmod 755 "$HOME_DIR/adshim.so"

echo "== Autodarts"
BIN=$HOME_DIR/.local/bin/autodarts
if [ -x "$BIN" ] && ! on "$AD_REINSTALL"; then
  echo "Already installed; set AD_REINSTALL=yes to download again."
else
  rc-service autodarts stop >/dev/null 2>&1 || true
  curl -fsSL https://autodarts.sh/sh/install.sh -o /tmp/autodarts-official-install.sh
  chmod 644 /tmp/autodarts-official-install.sh
  case "$AD_VERSION" in *[!0-9.]*) echo "AD_VERSION must look like 2.0.2."; exit 1 ;; esac
  set -- --headless; [ -n "$AD_VERSION" ] && set -- "$@" --version "$AD_VERSION"
  su autodarts -s /bin/sh -c "cd && HOME=$HOME_DIR LD_PRELOAD=$HOME_DIR/adshim.so bash /tmp/autodarts-official-install.sh $*"
  rm -f /tmp/autodarts-official-install.sh
fi
VER=$(su autodarts -s /bin/sh -c "cd && HOME=$HOME_DIR LD_PRELOAD=$HOME_DIR/adshim.so $BIN --version" 2>&1) \
  || { echo "Autodarts does not start: $VER"; exit 1; }
echo "$VER"

echo "== Board service"
cat > /etc/init.d/autodarts <<EOF
#!/sbin/openrc-run
name="autodarts"
description="Autodarts headless board"
command="$BIN"
command_args="run"
command_user="autodarts:autodarts"
directory="$HOME_DIR"
supervisor="supervise-daemon"
supervise_daemon_args="--env LD_PRELOAD=$HOME_DIR/adshim.so --env HOME=$HOME_DIR"
respawn_delay=5
respawn_max=0
output_log="/data/logs/autodarts.log"
error_log="/data/logs/autodarts.log"

start_pre() {
    checkpath -d -m 0755 /data/logs
    checkpath -f -o autodarts:autodarts -m 0644 /data/logs/autodarts.log
}

depend() {
    need net localmount
    after chronyd netclock
}
EOF
chmod 755 /etc/init.d/autodarts
rc-update add autodarts default >/dev/null
lbu include /etc/init.d/autodarts

if on "$OPT_CLOCK_SYNC"; then
  echo "== Clock sync before start"
  # Pis have no battery clock: without this, Autodarts can start with a wrong time and fail TLS.
  cat > /etc/init.d/netclock <<'EOF'
#!/sbin/openrc-run
description="Set the clock as soon as the network is up"

depend() {
    need net chronyd
    before autodarts
}

start() {
    ebegin "Syncing clock from network"
    chronyc online >/dev/null 2>&1
    chronyc burst 4/4 >/dev/null 2>&1
    chronyc waitsync 15 0 0 1 >/dev/null 2>&1
    chronyc makestep >/dev/null 2>&1
    eend 0
}
EOF
  chmod 755 /etc/init.d/netclock
  rc-update add chronyd default >/dev/null
  rc-update add netclock default >/dev/null
  lbu include /etc/init.d/netclock
fi

echo "== Tuning at boot"
TUNE=/etc/local.d/autodarts-tune.start
{
  echo '#!/bin/sh'
  echo '# Autodarts tuning, written by autodarts-install.sh'
  on "$OPT_CPU_PERFORMANCE" && echo 'for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo performance > "$g"; done'
  on "$OPT_WIFI_POWERSAVE_OFF" && echo 'iw dev wlan0 set power_save off 2>/dev/null'
  if [ -n "$OPT_CAMERA_EXPOSURE" ]; then
    case "$OPT_CAMERA_EXPOSURE" in *[!0-9]*) echo "OPT_CAMERA_EXPOSURE must be a number." >&2; exit 1 ;; esac
    echo 'for v in /dev/video*; do'
    echo "  v4l2-ctl -d \"\$v\" -c auto_exposure=1 -c exposure_time_absolute=$OPT_CAMERA_EXPOSURE 2>/dev/null"
    echo 'done'
  fi
  true
} > "$TUNE"
on "$OPT_WIFI_POWERSAVE_OFF" && apk add -q iw
chmod 755 "$TUNE"
rc-update add local default >/dev/null
lbu include "$TUNE"
sh "$TUNE" || true
# The same exposure is reapplied when a camera reconnects (cam-setup, installed by keepalive-install.sh).
printf '# Camera exposure applied whenever a camera appears (cam-setup). Empty = auto exposure.\nCAM_EXPOSURE=%s\n' "$OPT_CAMERA_EXPOSURE" > /etc/conf.d/autodarts-camera
lbu include /etc/conf.d/autodarts-camera

if on "$OPT_FAST_BOOT"; then
  sed -i 's/^#\{0,1\}rc_parallel=.*/rc_parallel="YES"/' /etc/rc.conf
  grep -q '^rc_parallel=' /etc/rc.conf || echo 'rc_parallel="YES"' >> /etc/rc.conf
fi

if on "$OPT_STATUS_LOGIN"; then
  cat > /etc/profile.d/autodarts-status.sh <<'EOF'
# Board status at login, written by autodarts-install.sh
alias ad="su - autodarts -s /bin/sh -c 'LD_PRELOAD=/data/autodarts/adshim.so ~/.local/bin/autodarts'"
[ -n "$PS1" ] || return 0
_ip=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
_mhz=$(( $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || echo 0) / 1000 ))
_temp=$(( $(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0) / 1000 ))
_ad=$(rc-service autodarts status 2>/dev/null | sed -n 's/.*status: //p')
printf ' Board     : %s\n' "$(tr -d '\0' < /proc/device-tree/model)"
printf ' Address   : %s\n' "${_ip:-no IP}"
printf ' CPU       : %s MHz, %s °C\n' "$_mhz" "$_temp"
printf ' Autodarts : %s\n' "${_ad:-unknown}"
printf ' ad = board screen | lbu commit -d = save settings\n\n'
unset _ip _mhz _temp _ad
EOF
  lbu include /etc/profile.d/autodarts-status.sh
fi

# Firmware settings (Bluetooth, overclock) live in config.txt on the boot partition.
if on "$OPT_DISABLE_BLUETOOTH" || [ -n "$OPT_OVERCLOCK" ]; then
  echo "== Firmware settings in $BOOT/config.txt"
  CFG=$BOOT/config.txt
  [ -f "$CFG" ] || { echo "$CFG not found; skipping firmware settings."; OPT_DISABLE_BLUETOOTH=; OPT_OVERCLOCK=; }
fi
if [ -f "$BOOT/config.txt" ] && { on "$OPT_DISABLE_BLUETOOTH" || [ -n "$OPT_OVERCLOCK" ]; }; then
  CFG=$BOOT/config.txt
  mount -o remount,rw "$BOOT"
  trap 'sync; mount -o remount,ro "$BOOT" 2>/dev/null' EXIT
  [ -f "$CFG.bak-autodarts" ] || cp "$CFG" "$CFG.bak-autodarts"
  if on "$OPT_DISABLE_BLUETOOTH"; then
    grep -qx 'dtoverlay=disable-bt' "$CFG" || printf '\n[all]\ndtoverlay=disable-bt\n' >> "$CFG"
  fi
  if [ -n "$OPT_OVERCLOCK" ]; then
    case "$PI:$OPT_OVERCLOCK" in
      4:2000) SECTION=pi4; OC_LINES="arm_freq=2000
over_voltage=6" ;;
      5:2600) SECTION=pi5; OC_LINES="arm_freq=2600
over_voltage_delta=25000" ;;
      5:2800|5:3000) SECTION=pi5; OC_LINES="arm_freq=$OPT_OVERCLOCK
over_voltage_delta=50000" ;;
      *) echo "OPT_OVERCLOCK=$OPT_OVERCLOCK is not offered for this board (Pi 4: 2000; Pi 5: 2600, 2800, 3000)."; exit 1 ;;
    esac
    # Replace the board's section ([pi4] or [pi5]) with the new clock settings.
    awk -v sec="[$SECTION]" '
      /^\[/ { skip = ($0 == sec) }
      !skip { print }' "$CFG" > "$CFG.new"
    printf '[%s]\n%s\n[all]\n' "$SECTION" "$OC_LINES" >> "$CFG.new"
    mv "$CFG.new" "$CFG"
    echo "Overclock set to $OPT_OVERCLOCK MHz; it applies after a reboot. Watch the temperature and use"
    echo "a good power supply and cooling. Set OPT_OVERCLOCK= (empty) and remove the [$SECTION] lines to undo."
  fi
fi

echo "== Saving and starting"
lbu commit -d
rc-service autodarts restart >/dev/null 2>&1 || rc-service autodarts start
sleep 5
if wget -qO /dev/null http://127.0.0.1:3180/api/state 2>/dev/null; then
  echo "Autodarts is running. Log in to the Pi and run  ad  to pair the board with your account and set up the cameras."
else
  echo "Autodarts started but does not answer yet. Check: tail /data/logs/autodarts.log"
fi
