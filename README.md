# Darts Scoreboard for AutoDarts

> **This code was generated with AI** (Claude by Anthropic), directed and tested by the author.
> See [About this code](#about-this-code).

Set up an [Autodarts](https://autodarts.io) board on a Raspberry Pi 4 or 5 running Alpine Linux,
and add a darts scoreboard and game manager to it. The Pi serves one web page, so any tablet,
phone, laptop or TV browser on your network can be the scoreboard. Detected darts come in
automatically from the board service; the page runs the games itself.

- **Autodarts on Alpine:** installs the official Autodarts board service on Alpine Linux, with
  optional optimizations (clock sync, CPU and Wi-Fi tuning, camera exposure, overclock).

- **Games:** X01 (301/501/701, double in/out), Cricket (standard, cut-throat, no points),
  Tactics, Mickey Mouse, Around the Clock, Shanghai, Baseball, Golf, Count-Up, Fives, Halve-It,
  Bob's 27, a checkout drill (121 style), Killer, Follow the Leader and Scram, with legs, sets
  and short rules for each game in the menu.
- **Scoring:** checkout routes, a live dartboard of the round's hits, the last scores of each
  player, a spoken score caller, tap-to-correct, *Fix scores* for earlier visits, undo.
- **Help at the board:** throw tips for every game (X01 set-ups and checkouts, Cricket, Killer and
  more), and the screen stays on during a game.
- **Displays:** a passive view for a TV (board, hits and the last 10 scores), scaled to any
  screen size, and a compact phone layout.
- **Sign-in and game lock:** users with passwords; starting a game locks the board to that
  user until the match ends, others watch read-only.
- **Settings page:** users, lights and the game lock are changed from the scoreboard itself.
- **Optional:** dartboard lights on a Wi-Fi plug, automatic backups and a watchdog, and access
  from the internet through Tailscale Funnel.

## Requirements

- A **Raspberry Pi 5 or 4** (tested on a Pi 5 with 8 GB) with the Autodarts cameras, running
  64-bit **Alpine Linux** in diskless mode. Configuration is saved by `lbu`, and a persistent
  partition is mounted at **`/data`** (see [Preparing the Pi](#preparing-the-pi)).
- An **Autodarts account** to pair the board with (at [autodarts.io](https://autodarts.io)).
- **Root SSH access** to the Pi, and internet access on the Pi for installing packages (`apk`).

If Autodarts already runs on the Pi as a service answering on
`http://127.0.0.1:3180/api/state`, set `INSTALL_AUTODARTS=no` and only the scoreboard is
installed.
- On your computer: `ssh` and `scp` (macOS and Linux have them; on Windows use WSL or Git Bash).

For the optional parts:

- **Lights:** a Tuya-based Wi-Fi plug (sold under many brands, e.g. Nedis SmartLife) on the same
  network as the Pi, and its **device ID** and **local key** (see [Lights](#lights)).
- **Internet access:** a free [Tailscale](https://tailscale.com) account (see
  [Tailscale](#optional-internet-access-with-tailscale)).

## Preparing the Pi

General steps for a fresh SD card (32 GB or more). See the
[Alpine wiki on the Raspberry Pi](https://wiki.alpinelinux.org/wiki/Raspberry_Pi) for details.

1. Download **Alpine Linux for Raspberry Pi, aarch64** from
   [alpinelinux.org/downloads](https://alpinelinux.org/downloads/).
2. Make a small FAT32 boot partition (about 2 GB) on the SD card, unpack the Alpine archive onto
   it, and leave the rest of the card unpartitioned.
3. Boot the Pi with a keyboard and screen and run `setup-alpine`:
   - Network: Wi-Fi or Ethernet, ideally with a fixed address.
   - SSH: OpenSSH. Add your public key for root (`/root/.ssh/authorized_keys`).
   - Disk: **none** (diskless). Store configs on the boot partition (`mmcblk0p1`), and keep the
     apk cache there too.
4. Create the data partition on the free space and mount it at `/data`:

   ```sh
   apk add e2fsprogs sfdisk util-linux
   echo ',,L' | sfdisk --append /dev/mmcblk0
   partx -a /dev/mmcblk0 2>/dev/null   # or reboot if /dev/mmcblk0p2 doesn't appear
   mkfs.ext4 -L autodarts /dev/mmcblk0p2
   mkdir -p /data
   echo 'LABEL=autodarts /data ext4 noatime,errors=remount-ro 0 2' >> /etc/fstab
   mount /data
   rc-update add localmount boot
   lbu commit -d
   ```

5. Plug in the cameras and reboot once to check that `/data` is mounted after boot.

## Installation

1. Download this repository to your computer.

2. Create your settings file from the example and fill it in:

   ```sh
   cp config.env.example config.env
   ```

   At minimum set `PI_HOST` (the Pi's address). `config.env` holds your secrets, such as
   passwords and keys. It is listed in `.gitignore`, so never commit it or share it.

3. Install from your computer:

   ```sh
   ./deploy.sh
   ```

   This copies the files to the Pi, runs `install.sh` there as root, and deletes `config.env`
   from the Pi afterwards. If you left `SCOREBOARD_ADMIN_PASSWORD` empty, it asks for the first
   user's password.

   Alternatively, copy the folder to the Pi yourself and run `sh install.sh` there as root.

4. Open `http://<pi-address>:8080` in a browser.

Everything starts at boot and is saved with `lbu`. To update, download the new version and run
`./deploy.sh` again: players, users and settings are kept.

## Configuration

### `config.env` (install time)

| Setting | Default | Meaning |
|---|---|---|
| `PI_HOST` | | Address of the Pi, used by `deploy.sh`. |
| `SCOREBOARD_PORT` | `8080` | Web port of the scoreboard. |
| `SCOREBOARD_ADMIN_USER` | empty | First user, created as admin. Empty: no sign-in until you add a user. |
| `SCOREBOARD_ADMIN_PASSWORD` | empty | **Secret.** Password for that user. Empty: asked during the install. |
| `INSTALL_AUTODARTS` | `yes` | Install the Autodarts board service. See [Autodarts board](#autodarts-board). |
| `AD_*`, `OPT_*` | | Autodarts version and optimizations, see the same section. |
| `INSTALL_PUBLIC_VIEW` | `yes` | Read-only copy for sharing (see below). |
| `INSTALL_MAINTENANCE` | `yes` | Weekly backup, daily log trim and a hardware watchdog. |
| `INSTALL_LIGHTS` | `no` | Lights on a Wi-Fi plug. |
| `INSTALL_TAILSCALE` | `no` | Internet access through Tailscale Funnel. |
| `LIGHTS_*` | | Plug settings, see [Lights](#lights). |
| `TS_*` | | Tailscale settings, see [Tailscale](#optional-internet-access-with-tailscale). |

### Settings page (any time)

Admins find **Settings** at the bottom of the scoreboard menu. While nobody has signed up yet,
anyone on the home network can open it to create the first user.

- **Users:** add users, change passwords, make or remove admins, remove users. The first user is
  always an admin, and the last admin can't be removed.
- **Lights:** plug device ID, IP address, local key, protocol version, both switch-off times, and
  automatic / always on / always off. Changes apply within a few seconds.
- **Game lock:** how long an unused lock lasts before it is released (default 3 hours).
- **Secure address (HTTPS):** where devices on the home network are sent, e.g. the Tailscale
  `/play/` address. Empty: no redirect.

Per-device options (score caller, board address) are in the menu itself.

Users can also be managed on the Pi with `scoreboard-user` (`add`, `passwd`, `del`, `admin`,
`list`, `unlock`).

## Using it

- **Sign-in:** once a user exists, the browser asks for a name and password. *Sign out* is next
  to your name in the menu.
- **Lights:** with the lights installed, a *Lights* button on the game screen and in the menu cycles
  automatic → on → off (the player holding the board, or anyone while no game is locked).
- **Keep screen on / Throw tips:** per-device switches in the menu. Keeping the screen on works
  best over HTTPS (for example the Tailscale `/play/` link); on plain HTTP a silent video is used,
  which works on most phones.
- **Updates:** open pages reload themselves after an update, except in the middle of a game.
- **Game lock:** starting a game locks the board to you. Others see your game read-only until the
  match ends or you press *End game*. An admin can force-unlock it.
- **TV:** open the menu's *Open passive display*, or `http://<pi-address>:8080/#passive`.
- **Corrections:** tap a dart to fix it, or use *Fix scores* for earlier visits.

## Autodarts board

`scripts/autodarts-install.sh` installs the board service:

- Downloads Autodarts with its **official installer** (`autodarts.sh`, headless) as the user
  `autodarts`, home `/data/autodarts`. No Autodarts files are included in this repository.
- Runs the official glibc build on Alpine through `gcompat`, plus a tiny shim
  (`scripts/adshim.c`, compiled during the install) that adds the two glibc functions gcompat
  lacks.
- Adds an OpenRC service `autodarts`, started at boot and restarted if it stops. Its log is
  `/var/log/autodarts.log`.
- Already installed? It's left alone unless `AD_REINSTALL=yes`. `AD_VERSION` pins a version.

After the install, log in to the Pi and run **`ad`** to pair the board with your Autodarts
account and set up the cameras. No account details are stored by these scripts.

Optimizations, each set in `config.env`:

| Setting | Default | Effect |
|---|---|---|
| `OPT_CLOCK_SYNC` | `yes` | Sets the clock from the network before Autodarts starts. A Pi has no battery clock, and a wrong time breaks secure connections. |
| `OPT_CPU_PERFORMANCE` | `yes` | CPU governor *performance*: full speed all the time for a steadier detection rate. |
| `OPT_WIFI_POWERSAVE_OFF` | `yes` | No Wi-Fi power saving, for lower and steadier latency. |
| `OPT_CAMERA_EXPOSURE` | empty | A number (e.g. `100`) fixes a short exposure on all cameras, which helps with motion blur under bright light. Empty keeps auto exposure. |
| `OPT_DISABLE_BLUETOOTH` | `yes` | Turns Bluetooth off in `config.txt`. |
| `OPT_FAST_BOOT` | `yes` | Starts services in parallel. |
| `OPT_OVERCLOCK` | empty | Pi 4: `2000`; Pi 5: `2600`, `2800` or `3000` MHz, in `config.txt`. Needs good cooling and the official power supply. Applies after a reboot. |
| `OPT_STATUS_LOGIN` | `yes` | Shows board, address, CPU and Autodarts status at login, and adds the `ad` command. |

The original `config.txt` is kept as `config.txt.bak-autodarts` on the boot partition.

## Optional parts

### Public read-only view

A copy of the passive display that shows the running game but has no controls, no sign-in and
nothing that can change data. It listens only inside the Pi (`127.0.0.1:8081`); share it with
Tailscale Funnel (below) or another tunnel.

### Health check (`INSTALL_KEEPALIVE`)

`darts-keepalive` runs a minute after boot and then every 5 minutes. It:

- starts or restarts the scoreboard, the public view and the lights service if they have stopped
  or don't answer, and starts Autodarts if its service has stopped;
- checks that every camera in the Autodarts config is on its USB port with its usual `/dev/video`
  number. When a camera drops off USB and comes back (a power dip, a loose cable), it gets a new
  number and Autodarts no longer matches it to its calibration. The check then re-attaches the
  cameras in order and restarts Autodarts, which restores all calibrations;
- restores the Tailscale Funnel routes listed in `/data/scoreboard/data/funnel-routes` (for
  example `/ 8081` and `/play 8080`). To stop sharing for good, empty that file before turning
  Funnel off; otherwise the routes come back;
- once a day, checks that every installed package can be reinstalled from the SD-card cache at
  boot (a diskless Pi reinstalls them at every start) and refreshes the cache if not.

A camera that reconnects also gets its fixed exposure back (`cam-setup`, run by `mdev`), set by
`OPT_CAMERA_EXPOSURE` (stored in `/etc/conf.d/autodarts-camera`).

If a secure address is set, the home address checks it first and only sends devices there when it
answers; otherwise the scoreboard opens on the home address.

### Maintenance

- **Backup:** `pi-backup` runs weekly and keeps five archives in `/data/backups`. They contain
  passwords and keys, so copy them somewhere safe and private:
  `scp "root@<pi-address>:/data/backups/pi-backup-*.tar.gz" .`
- **Logs on the SD card:** `/data/logs` holds the system and kernel log (`messages`), `autodarts.log`,
  `lights.log`, `darts-keepalive.log` and `cameras.log`, so they survive a reboot. They are trimmed
  daily once they pass 5 MB.
- **Watchdog:** the Pi restarts itself if it hangs for 30 seconds.

### Lights

The lights service switches a Tuya Wi-Fi plug on when the board starts, a dart is detected or a
game is started in the scoreboard. It switches it off after `LIGHTS_IDLE_MINUTES` without
board activity or `LIGHTS_NO_SCORE_MINUTES` without a new dart. It talks to the plug on your
own network; no cloud is needed after setup.

To get the plug's **device ID** and **local key** (once):

1. Pair the plug with the **Smart Life** or **Tuya Smart** app. White-label apps often can't be
   linked to a developer account.
2. Create a free account at [iot.tuya.com](https://iot.tuya.com) and a *Cloud* project
   (*Smart Home*). Select the data center that matches your app account in the upper right
   corner of the page.
3. In the project, open *Devices* → *Link App Account* and scan the QR code with the app.
4. On any computer with Python, run `pip install tinytuya` and then `python -m tinytuya wizard`.
   Enter the project's Access ID and Access Secret. It lists every plug with its `id`, `key` and
   IP address.

Put the values in `config.env` (`LIGHTS_DEVICE_ID`, `LIGHTS_LOCAL_KEY`, `LIGHTS_IP`) or on the
Settings page. Reserve the plug's IP address in your router. Re-pairing the plug creates a new
key.

The Tuya Access Secret is only needed for the wizard. Don't store it on the Pi, and reset it if
it has been shared.

### Optional: internet access with Tailscale

[Tailscale Funnel](https://tailscale.com/kb/1223/funnel) gives the Pi a public HTTPS address,
`https://<name>.<tailnet>.ts.net`, without opening ports on your router. Visitors need only a
browser. Only the Pi runs Tailscale.

Settings in `config.env`:

| Setting | Default | Meaning |
|---|---|---|
| `INSTALL_TAILSCALE` | `no` | Set to `yes` to install. |
| `TS_HOSTNAME` | `autodarts-pi` | Machine name; becomes the first part of the address. |
| `TS_AUTHKEY` | empty | **Secret, optional.** A Tailscale auth key (`tskey-auth-…`) to log in without a browser. Empty: the install prints a login link and waits. |
| `TS_FUNNEL_PUBLIC` | `yes` | Public read-only view at `https://<name>.<tailnet>.ts.net/`. Needs `INSTALL_PUBLIC_VIEW=yes`. |
| `TS_FUNNEL_PLAY` | `no` | Full scoreboard with sign-in at `/play/`. Only enabled if at least one scoreboard user exists. |
| `TS_HTTPS_REDIRECT` | `yes` | With `/play/` on: devices that open the home address are sent to the HTTPS address, so sign-in is encrypted and *Keep screen on* works. Open `http://<pi-address>:8080/?local` to stay on the home address (e.g. when the internet is down). Changeable later on the Settings page (*Secure address*). |

Then:

1. Run `./deploy.sh`. Without an auth key, open the printed link and log in to Tailscale.
2. If Tailscale says Funnel isn't enabled for your account, open the link it prints, allow Funnel
   (and HTTPS certificates), and run `./deploy.sh` again.
3. A new address can take a few minutes to appear in DNS.

The login is kept in `/data/tailscale`, so it survives reboots. Turn sharing off on the Pi with
`tailscale funnel --https=443 off`.

On the internet, `/` shows the read-only view to anyone who has the link. `/play/` always asks
for a scoreboard sign-in, so create users with strong passwords before enabling it.

## Troubleshooting

**Cameras disappear, or calibration is lost after a while.** Almost always power. A Raspberry Pi 5
gives its USB ports only about 600 mA in total unless its supply negotiates 5 A, and three Autodarts
cameras ask for about 1.5 A. Use the official Raspberry Pi 27 W USB-C supply (5 V / 5 A), or power
the cameras through a powered USB hub. Check on the Pi:
`hexdump -e '1/4 "%u\n"' /proc/device-tree/chosen/power/max_current` (5000 is good; around 900
or 3000 means the USB ports are limited). Don't overclock while power is marginal
(`OPT_OVERCLOCK` empty). `/data/logs/cameras.log` and `darts-keepalive.log` show every reconnect.

**Cameras with the same serial number.** Some camera batches report identical serials, so
Autodarts tells them apart only by USB port. Keep every camera in the same port; moving them swaps
their calibrations.

**Something stops working after a reboot.** A diskless Pi reinstalls its packages from the SD-card
cache at every start; a package missing from the cache silently doesn't come back. Fix it with
`apk cache sync && lbu commit -d`. The health check does this daily.

**Where are the logs?** In `/data/logs` (see Maintenance).

## Security notes

- The scoreboard uses HTTP Basic sign-in for its data (`/cgi-bin/`); the page itself holds no
  secrets. On the home network this is plain HTTP unless a secure address is set (then visitors are
  sent to HTTPS before signing in); through Tailscale it is HTTPS.
- The Autodarts board service (port 3180) has no sign-in of its own. Don't expose it to the
  internet; the scoreboard reaches it through the Pi on HTTPS pages.
- Passwords are stored hashed in `/data/scoreboard-auth/`. The plug key is stored in
  `/data/lights/config.json`. Both are readable only by root and the web server.

## Files and ports

| Path / port | What |
|---|---|
| `:8080` | Scoreboard (all interfaces). |
| `127.0.0.1:8081` | Public read-only view (local only). |
| `:3180` | Autodarts board service (no sign-in; keep it off the internet). |
| `/data/autodarts` | Autodarts and the glibc shim. |
| `/data/scoreboard` | Web page (`app.html`, served uncached by `cgi-bin/index.cgi`), CGI scripts, player list, game lock. |
| `/data/scoreboard-auth` | Users, admins. |
| `/data/scoreboard-public` | Read-only copy. |
| `/data/lights` | Lights service and its settings. |
| `/data/backups` | Backups. |
| `/data/logs` | Logs (kept across reboots). |
| `/data/tailscale` | Tailscale login state. |

## About this code

All code, scripts and documentation in this repository were generated with AI (Claude by
Anthropic) in a conversation with the author, written specifically for this project and tested
on the author's own Autodarts board. No code was copied from other projects:

- The repository contains no third-party code. Programs it relies on are installed from their
  own sources at install time (see below).
- The files were checked for licence headers, attribution notes and links to outside code;
  there are none.
- Darts rules are common knowledge. The board drawing uses the standard published dartboard
  measurements, and checkout routes are calculated, not taken from a table.

Like any AI output, it may resemble existing code by coincidence; that can't be ruled out
completely. Review it before relying on it, and report anything you recognise as copied.

## Third-party software

Installed on the Pi by the scripts, not included in this repository:

| Software | Licence | Used for |
|---|---|---|
| [Autodarts](https://autodarts.io) | Proprietary, by Autodarts | The board service, downloaded from its official installer |
| [gcompat](https://git.adelielinux.org/adelie/gcompat) | NCSA | Running the glibc build of Autodarts on Alpine |
| [BusyBox](https://busybox.net) (httpd and tools) | GPL-2.0 | Web server, scripts |
| [Python](https://www.python.org) | PSF License | Lights service |
| [tinytuya](https://github.com/jasonacox/tinytuya) | MIT | Talking to the Wi-Fi plug |
| [Tailscale](https://tailscale.com) | BSD-3-Clause | Optional internet access |

Autodarts is a separate product and is not part of this project: the scripts download it from
its official source, and its own licence terms apply. This project is not affiliated
with Autodarts, Tuya, Nedis or Tailscale.

## License

[MIT](LICENSE) © 2026 teemusaila
