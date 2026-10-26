# Darts Scoreboard for AutoDarts

Installers for an Autodarts board on a Raspberry Pi 4/5 with Alpine Linux, plus a web scoreboard.
Read README.md first; it is the user documentation. All code here was generated with AI and is MIT
licensed; keep the AI notice at the top of every script.

## Layout

- `install.sh` runs on the Pi and calls `scripts/*-install.sh` according to `config.env`.
  `deploy.sh` runs on the user's computer: copies the folder to the Pi and runs `install.sh`.
- `scripts/scoreboard-install.sh`: the scoreboard. The entire web page is one heredoc (`EOF_OCHE`)
  written to `/data/scoreboard/app.html`; small busybox CGI scripts (also heredocs) provide the data:
  players, game, board, lock, settings, lights, login. Sign-in is HTTP Basic on `/cgi-bin`.
- `scripts/autodarts-install.sh` + `scripts/adshim.c`: Autodarts via its official installer, gcompat
  and a glibc shim; optimizations.
- `scripts/keepalive-install.sh`: health check (services, cameras, Funnel routes, package cache).
- Others: public read-only view, lights (Tuya plug, Python), maintenance (backups, logs, watchdog),
  Tailscale Funnel.

## Constraints

- The Pi side is busybox: POSIX `sh` (no bash features), busybox `wget`/`nc`/`httpd`, OpenRC.
- Alpine runs diskless: files outside `/data` survive a reboot only after `lbu include` +
  `lbu commit -d`; packages only if they're in the SD-card cache (`apk cache sync`).
- Installers must stay re-runnable and keep users' data (players, users, settings).
- No secrets or personal values in the repo: `config.env` is ignored by git; keys and passwords live
  only on the Pi.

## Before committing

Run `tools/check.sh`. Update README.md when behaviour or settings change.
