#!/bin/sh
# This code was generated with AI (Claude by Anthropic). MIT License, see LICENSE and README.
# scoreboard-install.sh: Darts Scoreboard, a darts scoreboard and game manager served by the Autodarts Pi.
#
# Run as root:   sh scoreboard-install.sh
#
# Installs a single web page to /data/scoreboard and serves it on port 8080 with
# Busybox httpd. Open http://<pi-address>:8080 on any tablet, phone, laptop or TV browser.
# The page reads detected darts from the board service (port 3180) and runs the games
# itself: X01, Cricket (standard, cut-throat, no points), Around the Clock, Shanghai,
# Count-Up, Halve-It, Bob's 27 and Killer, with legs, checkout routes, a live dartboard of
# the round's hits, corrections, a Fix scores list for earlier visits, undo and a spoken
# score caller.
# Sign-in: add users with "scoreboard-user add NAME" (until the first user exists the page is open).
# Starting a game locks the board to that user until the match ends or they end it; other users
# then see the game read-only. Admins can force-unlock; a lock idle for 3 hours is dropped.
# The player list is shared by all devices (kept in /data/scoreboard/data). Games in progress are
# stored in the browser of the device you use. Re-running this script updates the page
# and keeps the player list.

set -e
DIR=/data/scoreboard
AUTH=/data/scoreboard-auth   # users, admins and the lock helper; outside the web root
PORT=${SCOREBOARD_PORT:-8080}

[ "$(id -u)" = 0 ] || { echo "Run as root."; exit 1; }
grep -q ' /data ' /proc/mounts || { echo "/data is not mounted."; exit 1; }

echo "== Installing the web server"
apk add -q busybox-extras
HTTPD=$(command -v httpd) || { echo "httpd not found after installing busybox-extras."; exit 1; }

echo "== Writing the scoreboard to $DIR"
mkdir -p "$DIR"
cat > "$DIR/app.html" <<'EOF_OCHE'
<!doctype html>
<html lang="en">
<!-- Darts Scoreboard for AutoDarts. This code was generated with AI (Claude by Anthropic). MIT License. -->
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#04060d">
<title>Darts Scoreboard</title>
<style>
:root {
  --z: 1;                  /* page scale, set by the script in <head> */
  --cabinet: #0a0f1d;      /* panels */
  --cabinet-deep: #04060d; /* night background */
  --sisal: #e6f7ff;        /* main text, cool white */
  --sisal-ink: #04060d;
  --wire: #7d8db3;         /* secondary text */
  --glow: #2ef2ff;         /* neon cyan: active player, focus */
  --red: #ff3dbb;          /* neon magenta: bust, treble/double ring */
  --green: #a4ff3a;        /* neon lime: checkout, closed */
  --line: rgba(46, 242, 255, .16);
  --halo: 0 0 6px rgba(46, 242, 255, .9), 0 0 22px rgba(46, 242, 255, .55), 0 0 48px rgba(46, 242, 255, .3);
  --font: "Bahnschrift", "DIN Alternate", "Roboto Condensed", "Arial Narrow", system-ui, sans-serif;
}
* { box-sizing: border-box; }
html, body { margin: 0; height: 100%; }
body {
  background: radial-gradient(120% 80% at 50% -10%, #0b1a33 0%, var(--cabinet-deep) 60%) fixed, var(--cabinet-deep);
  color: var(--sisal);
  font-family: var(--font);
  font-variant-numeric: tabular-nums;
  -webkit-tap-highlight-color: transparent;
  overflow: hidden;
}
button {
  font: inherit; color: inherit; background: none; border: 0; cursor: pointer;
  touch-action: manipulation;
}
button:focus-visible, input:focus-visible { outline: 3px solid var(--glow); outline-offset: 3px; }
.screen { display: none; height: calc(100dvh / var(--z)); }
.screen.on { display: flex; flex-direction: column; }

/* ---------- setup ---------- */
#setup { overflow-y: auto; padding: 32px max(20px, calc(6vw / var(--z))) 40px; gap: 28px; background: transparent; }
#setup h1 { color: var(--glow); text-shadow: var(--halo); }
#setup h1 { margin: 0; font-size: clamp(40px, calc(7vw / var(--z)), 72px); font-weight: 700; letter-spacing: -.01em; line-height: 1; }
#setup h2 { margin: 0 0 12px; font-size: 20px; font-weight: 600; color: var(--wire); }
#settings { overflow-y: auto; padding: 20px max(16px, calc(4vw / var(--z))) 32px; gap: 18px; }
#settings .shead { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
#settings h1 { margin: 0; font-size: 34px; color: var(--glow); text-shadow: var(--halo); }
#settings h2 { margin: 0 0 8px; font-size: 18px; font-weight: 600; color: var(--wire); }
.sgroup { padding: 14px 16px; border: 1px solid var(--line); border-radius: 14px; background: rgba(10, 15, 29, .7); max-width: 900px; }
.smsg { margin: 0; min-height: 1.3em; font-size: 15px; color: var(--green); }
.smsg.err { color: var(--red); }
.ulist { list-style: none; margin: 0 0 10px; padding: 0; display: grid; gap: 6px; }
.ulist li { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; }
.ulist .uname { min-width: 9em; font-size: 17px; }
.ulist .badge { font-size: 12px; padding: 2px 8px; border: 1px solid currentColor; border-radius: 999px; color: var(--glow); }
.ulist button, .ulist input { font: inherit; font-size: 14px; }
.ulist button { padding: 5px 10px; border: 1px solid var(--line); border-radius: 8px; }
.ulist button.del { color: var(--red); border-color: rgba(255, 61, 187, .4); }
.sform { display: flex; flex-wrap: wrap; align-items: flex-end; gap: 10px 14px; margin-top: 8px; }
.sform label { display: flex; flex-direction: column; gap: 4px; font-size: 13px; color: var(--wire); }
.sform label.check { flex-direction: row; align-items: center; gap: 6px; font-size: 15px; color: var(--sisal); padding-bottom: 10px; }
.sform input, .sform select, .ulist input { font: inherit; font-size: 16px; padding: 8px 10px; border-radius: 10px; border: 1px solid var(--line); background: var(--cabinet-deep); color: var(--sisal); min-width: 0; }
.sform input[type="number"] { width: 6em; }
.sform input[name="device_id"], .sform input[name="local_key"] { width: 15em; }
.sform input[type="checkbox"] { width: 18px; height: 18px; padding: 0; }
.row { display: flex; flex-wrap: wrap; gap: 10px; }
.chip {
  padding: 12px 18px; border-radius: 999px; border: 2px solid var(--line);
  font-size: 20px; min-height: 52px;
}
.chip[aria-pressed="true"] { background: rgba(46, 242, 255, .1); color: var(--glow); border-color: var(--glow); box-shadow: 0 0 14px rgba(46, 242, 255, .45), inset 0 0 10px rgba(46, 242, 255, .2); text-shadow: 0 0 8px rgba(46, 242, 255, .7); }
.chip .order { font-size: 14px; opacity: .7; margin-left: 6px; }
.add { display: flex; gap: 10px; margin-top: 12px; max-width: 520px; }
.add input {
  flex: 1; min-width: 0; font: inherit; font-size: 20px; padding: 12px 16px; border-radius: 12px;
  border: 2px solid var(--line); background: var(--cabinet-deep); color: var(--sisal);
}
.hint { color: var(--wire); font-size: 16px; margin: 8px 0 0; }
.start {
  align-self: flex-start; padding: 18px 40px; border-radius: 14px; font-size: 26px; font-weight: 700;
  background: var(--glow); color: var(--sisal-ink); box-shadow: 0 0 18px rgba(46, 242, 255, .7), 0 0 50px rgba(46, 242, 255, .35);
}
.start:disabled { opacity: .3; box-shadow: none; cursor: not-allowed; }
.link { color: var(--wire); text-decoration: underline; font-size: 16px; padding: 6px 0; }

/* ---------- game ---------- */
#game { background: transparent; }
.bar {
  display: flex; align-items: center; gap: 14px; padding: 10px 18px;
  border-bottom: 1px solid var(--line); color: var(--wire); font-size: 17px; min-height: 52px;
}
.bar .grow { flex: 1; }
.dot { width: 12px; height: 12px; border-radius: 50%; background: var(--wire); flex: none; }
.dot.ok { background: var(--green); box-shadow: 0 0 10px var(--green); }
.dot.wait { background: #ffc23d; box-shadow: 0 0 10px #ffc23d; }
.dot.off { background: var(--red); box-shadow: 0 0 10px var(--red); }
.bar button { padding: 8px 14px; border-radius: 10px; border: 1px solid var(--line); color: var(--sisal); }

.players { flex: 1; display: grid; grid-auto-flow: column; grid-auto-columns: 1fr; min-height: 0; }
.player {
  display: flex; flex-direction: column; justify-content: center; align-items: center; gap: 6px;
  padding: 16px; border-right: 1px solid var(--line); text-align: center; min-width: 0;
  transition: background-color .25s, color .25s;
}
.player:last-child { border-right: 0; }
.player .name { font-size: clamp(22px, calc(3.2vw / var(--z)), 40px); font-weight: 600; max-width: 100%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.player .legs { font-size: clamp(15px, calc(1.8vw / var(--z)), 20px); color: var(--wire); }
.player { container-type: inline-size; }
.player .score { font-size: clamp(56px, 40cqi, 220px); font-weight: 700; line-height: .9; letter-spacing: -.03em; }
.player .route { font-size: clamp(18px, calc(2.4vw / var(--z)), 30px); min-height: 1.3em; color: var(--green); font-weight: 600; text-shadow: 0 0 10px rgba(164, 255, 58, .7); }
.player .recent { display: flex; justify-content: center; flex-wrap: wrap; gap: 4px 10px; min-height: 1.4em; font-size: clamp(14px, calc(1.7vw / var(--z)), 20px); color: var(--wire); }
.player .recent .new { color: var(--sisal); font-weight: 700; }
.player .stats { font-size: clamp(14px, calc(1.6vw / var(--z)), 18px); color: var(--wire); }
.player .score { text-shadow: 0 0 18px rgba(230, 247, 255, .18); }
.player.active { background: linear-gradient(180deg, rgba(46, 242, 255, .09), rgba(46, 242, 255, .02)); box-shadow: inset 0 0 0 2px var(--glow), inset 0 0 60px rgba(46, 242, 255, .18), 0 0 30px rgba(46, 242, 255, .25); }
.player.active .name { color: var(--glow); text-shadow: 0 0 10px rgba(46, 242, 255, .6); }
.player.active .score { color: var(--glow); text-shadow: var(--halo); }
.player.active.bust { background: linear-gradient(180deg, rgba(255, 61, 187, .12), rgba(255, 61, 187, .03)); box-shadow: inset 0 0 0 2px var(--red), inset 0 0 60px rgba(255, 61, 187, .22), 0 0 30px rgba(255, 61, 187, .3); }
.player.active.bust .name, .player.active.bust .route { color: var(--red); text-shadow: 0 0 10px rgba(255, 61, 187, .7); }
.player.active.bust .score { color: var(--red); text-shadow: 0 0 6px rgba(255, 61, 187, .9), 0 0 24px rgba(255, 61, 187, .6), 0 0 50px rgba(255, 61, 187, .35); }

.visit {
  display: grid; grid-template-columns: repeat(3, 1fr) auto; gap: 12px;
  padding: 14px 18px calc(14px + env(safe-area-inset-bottom)); border-top: 1px solid var(--line);
  background: rgba(10, 15, 29, .85);
}
.dart {
  min-height: 84px; border-radius: 14px; border: 2px dashed var(--line);
  font-size: clamp(28px, calc(4.5vw / var(--z)), 48px); font-weight: 700;
}
.dart.hit { border-style: solid; border-color: var(--glow); color: var(--glow); box-shadow: 0 0 14px rgba(46, 242, 255, .45), inset 0 0 14px rgba(46, 242, 255, .15); text-shadow: 0 0 10px rgba(46, 242, 255, .7); }
.dart.edited { border-color: var(--green); color: var(--green); box-shadow: 0 0 14px rgba(164, 255, 58, .45); text-shadow: 0 0 10px rgba(164, 255, 58, .7); }
.total { min-width: 120px; display: flex; flex-direction: column; justify-content: center; align-items: flex-end; padding-right: 6px; }
.total b { font-size: clamp(36px, calc(6vw / var(--z)), 64px); line-height: 1; }
.total b { color: var(--glow); text-shadow: var(--halo); }
.total span { font-size: 16px; color: var(--wire); }

.banner {
  position: fixed; inset: 0; display: none; place-items: center; text-align: center;
  background: rgba(4, 6, 13, .9); backdrop-filter: blur(4px); z-index: 5; padding: 24px;
}
.banner.on { display: grid; }
.banner h2 { margin: 0 0 8px; font-size: clamp(44px, calc(9vw / var(--z)), 110px); line-height: 1; }
.banner h2 { color: var(--glow); text-shadow: var(--halo); }
.banner p { margin: 0 0 24px; font-size: 22px; color: var(--wire); }
.banner .row { justify-content: center; }

/* ---------- keypad ---------- */
.pad { position: fixed; inset: 0; display: none; background: rgba(0,0,0,.6); z-index: 6; align-items: flex-end; justify-content: center; }
.pad.on { display: flex; }
.pad .sheet { background: var(--cabinet); box-shadow: 0 -10px 40px rgba(46, 242, 255, .2); border-top: 1px solid var(--glow); width: min(760px, 100%); border-radius: 18px 18px 0 0; padding: 18px 18px calc(18px + env(safe-area-inset-bottom)); }
.pad .mult { display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; margin-bottom: 10px; }
.pad .nums { display: grid; grid-template-columns: repeat(7, 1fr); gap: 8px; }
.pad button { min-height: 56px; border-radius: 10px; border: 1px solid var(--line); font-size: 22px; font-weight: 600; }
.pad .mult button[aria-pressed="true"] { color: var(--glow); border-color: var(--glow); box-shadow: 0 0 12px rgba(46, 242, 255, .5); }
.pad .foot { display: flex; justify-content: space-between; margin-top: 12px; }
#pad { z-index: 7; }
/* passive display */
#passive { background: transparent; }
.pbar { display: flex; align-items: center; gap: 14px; padding: 8px 18px; color: var(--wire); font-size: 17px; border-bottom: 1px solid var(--line); }
.pbar .grow { flex: 1; }
#p-lock { color: var(--red); font-weight: 600; }
.pbar button { padding: 8px 14px; border-radius: 10px; border: 1px solid var(--line); color: var(--sisal); opacity: .6; }
.pmain { flex: 1; display: flex; min-height: 0; }
.pboard { width: min(calc(88vh / var(--z)), calc(50vw / var(--z))); flex: none; display: flex; flex-direction: column; justify-content: center; gap: 10px; padding: 14px; border-right: 1px solid var(--line); }
.pboard svg { width: 100%; height: auto; display: block; }
.pcap { font-size: clamp(16px, calc(2vw / var(--z)), 24px); color: var(--wire); text-align: center; }
.phits { display: flex; flex-wrap: wrap; justify-content: center; gap: 8px; min-height: 2.2em; }
.phits span { padding: 4px 12px; border-radius: 999px; border: 2px solid; font-size: clamp(18px, calc(2.4vw / var(--z)), 32px); font-weight: 700; }
.pplayers { flex: 1; display: flex; flex-direction: column; min-width: 0; overflow-y: auto; }
.pp { flex: 1; min-height: 120px; display: grid; grid-template-columns: 1fr auto; align-items: center; gap: 4px 16px; padding: 12px 22px; border-bottom: 1px solid var(--line); }
.pp .nm { font-size: clamp(20px, calc(3vw / var(--z)), 40px); font-weight: 600; }
.pp .nm small { margin-left: 12px; font-size: .55em; color: var(--wire); font-weight: 400; }
.pp .big { grid-row: span 2; font-size: clamp(56px, calc(11vw / var(--z)), 150px); font-weight: 700; line-height: 1; text-align: right; }
.pp .sub { font-size: clamp(14px, calc(1.8vw / var(--z)), 22px); color: var(--green); }
.pp .rec { grid-column: 1 / -1; display: flex; flex-wrap: wrap; gap: 4px 14px; font-size: clamp(16px, calc(2.2vw / var(--z)), 30px); color: var(--wire); min-height: 1.4em; }
.pp .rec .new { color: var(--sisal); font-weight: 700; }
.pp.active { background: linear-gradient(90deg, rgba(46, 242, 255, .09), rgba(46, 242, 255, .02)); box-shadow: inset 4px 0 0 var(--glow); }
.pp.active .nm, .pp.active .big { color: var(--glow); text-shadow: var(--halo); }
.pp.active.bust .nm, .pp.active.bust .big { color: var(--red); text-shadow: 0 0 24px rgba(255, 61, 187, .6); }
.pp.out { opacity: .45; }
@media (max-width: 900px) { .pmain { flex-direction: column; overflow-y: auto; } .pboard { width: 100%; border-right: 0; border-bottom: 1px solid var(--line); } .pboard svg { width: min(calc(70vw / var(--z)), calc(60vh / var(--z))); margin: 0 auto; } }
#fix .sheet { max-height: calc(80dvh / var(--z)); display: flex; flex-direction: column; }
#fix h3 { margin: 0 0 4px; font-size: 24px; color: var(--glow); text-shadow: 0 0 10px rgba(46, 242, 255, .6); }
#fix p { margin: 0 0 12px; color: var(--wire); font-size: 16px; }
#fix-list { overflow-y: auto; display: flex; flex-direction: column; gap: 8px; }
.frow { display: flex; align-items: center; gap: 8px; padding: 8px 10px; border: 1px solid var(--line); border-radius: 12px; }
.frow .who { flex: 1; min-width: 0; font-size: 18px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.frow .who small { display: block; font-size: 13px; color: var(--wire); }
.frow .pts { min-width: 44px; text-align: right; font-size: 22px; font-weight: 700; color: var(--sisal); }
.frow button { min-width: 64px; min-height: 52px; padding: 0 10px; border-radius: 10px; border: 1px solid var(--glow); color: var(--glow); font-size: 22px; font-weight: 700; }
.frow button.add { border-style: dashed; border-color: var(--line); color: var(--wire); }
.frow.fixed { box-shadow: inset 0 0 0 2px var(--green); }

.raw { position: fixed; right: 12px; bottom: 120px; max-width: min(520px, calc(90vw / var(--z))); max-height: calc(40vh / var(--z)); overflow: auto;
  background: #000; color: var(--green); font: 13px/1.4 ui-monospace, monospace; padding: 10px; border-radius: 8px; display: none; z-index: 4; white-space: pre-wrap; }
.raw.on { display: block; }

@media (max-width: 700px) {
  .bar { flex-wrap: wrap; gap: 8px; padding: 8px 12px; font-size: 15px; }
  .bar #match-text { display: none; }
  .bar #conn-text { flex: 1; }
  .bar button { padding: 6px 10px; font-size: 15px; }
  .player .stats, .player .route, .player .recent { flex-basis: 100%; justify-content: flex-start; }
  .players { grid-auto-flow: row; grid-auto-rows: 1fr; grid-auto-columns: auto; }
  .player { border-right: 0; border-bottom: 1px solid var(--line); flex-direction: row; flex-wrap: wrap; justify-content: space-between; text-align: left; padding: 10px 16px; }
  .player .score { font-size: clamp(56px, calc(18vw / var(--z)), 96px); }
  .visit { grid-template-columns: repeat(3, 1fr); }
  .total { grid-column: 1 / -1; flex-direction: row; justify-content: space-between; align-items: baseline; }
}
@media (prefers-reduced-motion: reduce) { .player { transition: none; } }

/* ---------- additions for all games ---------- */
.manage { margin-top: 14px; padding: 16px; border: 1px solid var(--line); border-radius: 14px; max-width: 640px; background: rgba(10, 15, 29, .7); }
.manage ul { list-style: none; margin: 0 0 6px; padding: 0; display: grid; gap: 8px; }
.manage li { display: flex; gap: 8px; align-items: center; }
.manage li input { flex: 1; min-width: 0; font: inherit; font-size: 19px; padding: 9px 12px; border-radius: 10px; border: 1px solid var(--line); background: var(--cabinet-deep); color: var(--sisal); }
.manage li button { min-width: 46px; min-height: 46px; border-radius: 10px; border: 1px solid var(--line); font-size: 18px; }
.manage li button:disabled { opacity: .25; cursor: default; }
.manage li button.del { color: var(--red); border-color: rgba(255, 61, 187, .4); padding: 0 12px; }
.manage li .count { font-size: 14px; color: var(--wire); min-width: 4.5em; text-align: right; }
.rule { color: var(--wire); font-size: 17px; margin: 10px 0 0; max-width: 62ch; line-height: 1.4; }
.opt-group { margin-top: 16px; }
.who .link { margin-left: 10px; font-size: inherit; padding: 0; }
.rules { margin-top: 10px; max-width: 90ch; color: var(--wire); font-size: 16px; line-height: 1.4; }
.rules summary { display: inline-block; cursor: pointer; padding: 5px 14px; border: 1px solid var(--line); border-radius: 999px; color: var(--sisal); font-size: 15px; list-style: none; }
.rules summary::-webkit-details-marker { display: none; }
.rules summary::after { content: ' ▾'; color: var(--wire); }
.rules[open] summary::after { content: ' ▴'; }
.rules[open] summary { color: var(--glow); border-color: var(--glow); }
.rules ul { margin: 8px 0 0; padding-left: 1.2em; }
.rules li { margin: 2px 0; }
.rules li b { color: var(--sisal); font-weight: 600; }
.rules h3 { margin: 10px 0 0; font-size: 14px; font-weight: 600; color: var(--wire); }
.opt-group h3 { margin: 0 0 8px; font-size: 16px; font-weight: 600; color: var(--wire); }
/* Compact menu on tablets, laptops and TVs: the whole setup fits about 1200x900 without scrolling. */
@media (min-width: 701px) {
  #setup { padding: 20px max(20px, calc(4vw / var(--z))) 24px; gap: 16px; }
  #setup h1 { font-size: clamp(34px, calc(4.5vw / var(--z)), 52px); }
  #setup h2 { margin: 0 0 8px; font-size: 17px; }
  .row { gap: 8px; }
  .chip { padding: 8px 15px; font-size: 18px; min-height: 44px; }
  .hint { font-size: 14px; margin-top: 6px; }
  .rule { font-size: 15px; margin-top: 6px; max-width: 90ch; }
  #game-opts { display: flex; flex-wrap: wrap; gap: 0 28px; }
  .opt-group { margin-top: 10px; }
  .opt-group h3 { margin: 0 0 6px; font-size: 14px; }
  .start { padding: 13px 34px; font-size: 22px; }
  .add { margin-top: 0; }
}
.marks { display: grid; grid-template-columns: auto auto; gap: 2px 14px; margin-top: 6px; font-size: clamp(16px, calc(2vw / var(--z)), 24px); }
.marks .mk { display: contents; }
.marks .t { text-align: right; color: inherit; opacity: .75; }
.marks .m { text-align: left; font-weight: 700; min-width: 1.6em; letter-spacing: .05em; }
.marks .m.closed { color: var(--green); text-shadow: 0 0 8px rgba(164, 255, 58, .8); }
.player.out { opacity: .4; }
.player .tag { font-size: clamp(14px, calc(1.6vw / var(--z)), 18px); padding: 2px 10px; border-radius: 999px; border: 1px solid currentColor; }
.arena { flex: 1; display: flex; min-height: 0; }
.arena .players { flex: 1; }
.boardview { width: min(calc(46vh / var(--z)), calc(36vw / var(--z))); flex: none; display: flex; flex-direction: column; justify-content: center; gap: 10px; padding: 14px; border-left: 1px solid var(--line); }
.boardview svg { width: 100%; height: auto; display: block; }
.boardview .cap { font-size: 16px; color: var(--wire); text-align: center; }
.legend { display: flex; flex-wrap: wrap; justify-content: center; gap: 6px 14px; font-size: 16px; }
.legend i { display: inline-block; width: 12px; height: 12px; border-radius: 50%; margin-right: 6px; vertical-align: -1px; }
.bar .reset { color: var(--wire); }
@media (max-width: 700px) {
  .arena { flex-direction: column; }
  .boardview { width: 100%; border-left: 0; border-top: 1px solid var(--line); flex-direction: row; align-items: center; padding: 8px 12px; }
  .boardview svg { width: calc(34vw / var(--z)); }
  .boardview .side { flex: 1; }
}
@media (max-width: 700px) {
  .marks { display: flex; flex-wrap: wrap; gap: 4px 14px; flex-basis: 100%; }
  .marks .mk { display: inline-flex; gap: 4px; }
  .marks .m { min-width: 1em; }
  .arena { overflow-y: auto; }
  .arena .players { flex: none; grid-auto-rows: auto; }
  .player .score { font-size: clamp(48px, calc(18vw / var(--z)), 96px); }
}

/* ---------- compact phone layout (menu and game) ---------- */
@media (max-width: 700px) {
  /* menu */
  #setup { padding: 16px 16px 24px; gap: 14px; }
  #setup h1 { font-size: 32px; }
  #setup h2 { margin: 0 0 6px; font-size: 15px; }
  .row { gap: 6px; }
  .chip { padding: 7px 12px; font-size: 15px; min-height: 40px; border-width: 1.5px; }
  .hint { font-size: 13px; margin-top: 4px; }
  .rule { font-size: 13px; margin-top: 4px; line-height: 1.35; }
  #game-opts { display: flex; flex-wrap: wrap; gap: 0 16px; }
  .opt-group { margin-top: 8px; }
  .opt-group h3 { margin: 0 0 4px; font-size: 13px; }
  .start { padding: 11px 24px; font-size: 19px; border-radius: 12px; }
  .link { font-size: 14px; padding: 4px 0; }
  .add { margin-top: 0; }
  .add input { font-size: 15px; padding: 8px 10px; }
  .rules { font-size: 13px; margin-top: 6px; }
  .rules summary { font-size: 13px; padding: 4px 12px; }

  /* game: top bar in two short rows */
  .bar { gap: 6px; padding: 6px 10px; min-height: 0; font-size: 13px; }
  .bar button { padding: 5px 8px; font-size: 13px; border-radius: 8px; }
  .bar #conn-text { flex: 1 1 auto; }

  /* players: one compact row each, score on the right */
  .player {
    display: grid; grid-template-columns: minmax(0, 1fr) auto; column-gap: 12px; row-gap: 1px;
    align-items: center; justify-items: start; text-align: left; padding: 6px 14px;
  }
  .player > * { grid-column: 1; }
  .player .name { font-size: 19px; }
  .player .legs { font-size: 12px; }
  .player .score { grid-column: 2; grid-row: 1 / span 4; justify-self: end; font-size: 48px; line-height: 1; }
  .player .route { font-size: 14px; min-height: 0; }
  .player .route:empty { display: none; }
  .player .stats, .player .recent { font-size: 12px; min-height: 0; gap: 2px 8px; flex-basis: auto; }
  .player .recent:empty { display: none; }
  .marks { font-size: 13px; margin-top: 2px; }

  /* board: smaller, legend beside it */
  .boardview { padding: 4px 12px; gap: 10px; }
  .boardview svg { width: min(52vw, 30vh); flex: none; }
  .boardview .cap, .legend { font-size: 12px; }

  /* this visit: three darts and the total on one row */
  .visit { grid-template-columns: repeat(3, 1fr) auto; gap: 8px; padding: 8px 10px calc(8px + env(safe-area-inset-bottom)); }
  .dart { min-height: 52px; font-size: 24px; border-radius: 10px; }
  .total { grid-column: auto; flex-direction: column; justify-content: center; align-items: flex-end; min-width: 58px; padding-right: 2px; }
  .total b { font-size: 32px; }
  .total span { font-size: 11px; }
}
</style>
<script>
// Scale the whole page with the screen: the layout is designed for 1200x900 and zoomed to fill larger or
// smaller screens in proportion (TVs, 4K, small laptops). Phones keep their own layout. Viewport units in
// the CSS are divided by --z so they are not scaled twice.
(function () {
  function scale() {
    const w = innerWidth, h = innerHeight;
    const z = w <= 700 ? 1 : Math.min(4, Math.max(0.8, Math.min(w / 1200, h / 900)));
    document.documentElement.style.setProperty('--z', String(z));
    document.documentElement.style.zoom = String(z);
  }
  scale();
  addEventListener('resize', scale);
})();
</script>
</head>
<body>

<!-- Setup -->
<section id="setup" class="screen on" aria-labelledby="setup-title">
  <h1 id="setup-title">Darts Scoreboard</h1>
  <p class="hint who" id="who-line" hidden><span id="who"></span> <button class="link" id="btn-logout">Sign out</button></p>

  <div>
    <h2>Players</h2>
    <div class="row" id="roster"></div>
    <p class="hint" id="roster-hint">Tap names in throwing order.</p>
    <div class="row" style="margin-top:12px">
      <button class="chip" id="btn-last" hidden>Same players as last game</button>
      <button class="chip" id="btn-clear" hidden>Clear selection</button>
      <button class="chip" id="btn-manage" aria-expanded="false" aria-controls="manage">Manage list</button>
    </div>
    <div id="manage" class="manage" hidden>
      <ul id="manage-list"></ul>
      <form class="add" id="add-form">
        <input id="add-name" maxlength="16" placeholder="New player name" autocomplete="off" aria-label="New player name">
        <button class="chip" type="submit">Add player</button>
      </form>
      <p class="hint" id="sync-note"></p>
    </div>
  </div>

  <div>
    <h2>Game</h2>
    <div class="row" id="opt-game"></div>
    <p class="rule" id="game-rule"></p>
    <details class="rules" id="rules">
      <summary>Rules</summary>
      <ul id="rules-list"></ul>
      <h3>In every game</h3>
      <ul>
        <li>Players throw in the order you picked; the first thrower moves on by one each leg.</li>
        <li>A visit is three darts and ends when the darts are pulled out, or with Next player.</li>
        <li>Tap a dart to correct it, or use Fix scores to change an earlier visit.</li>
        <li>Win the leg count you chose (First to) to win the match.</li>
      </ul>
    </details>
    <div id="game-opts"></div>
  </div>

  <div>
    <h2>First to</h2>
    <div class="row" id="opt-legs"></div>
  </div>

  <div class="row" style="align-items:center; gap:24px">
    <button class="start" id="start" disabled>Start game</button>
    <button class="link" id="resume" hidden>Resume last game</button>
    <button class="link" id="open-passive">Open passive display (for a TV: shows the game running on another device)</button>
  </div>

  <div>
    <h2>Board</h2>
    <div class="add">
      <input id="api" aria-label="Board address" autocomplete="off">
      <button class="chip" id="api-save" type="button">Save</button>
    </div>
    <p class="hint">Address of the Autodarts board service. Usually the Pi's address with port 3180.</p>
    <div class="row" style="margin-top:10px">
      <button class="chip" id="opt-voice" aria-pressed="true">Score caller on</button>
      <button class="chip" id="opt-tips" aria-pressed="true">Throw tips on</button>
      <button class="chip" id="opt-awake" aria-pressed="true">Keep screen on</button>
      <button class="chip" id="btn-settings" hidden>Settings: users, lights, game lock</button>
    </div>

  </div>
</section>

<!-- Settings (admins; anyone while sign-in is off) -->
<section id="settings" class="screen" aria-labelledby="settings-title">
  <div class="shead"><h1 id="settings-title">Settings</h1><button class="chip" id="settings-close">Done</button></div>
  <p class="smsg" id="settings-msg" role="status"></p>

  <div class="sgroup">
    <h2>Users</h2>
    <p class="hint" id="users-note"></p>
    <ul class="ulist" id="users-list"></ul>
    <form class="sform" id="user-add">
      <label>Name <input name="uname" maxlength="24" autocomplete="off" required></label>
      <label>Password <input name="password" type="password" minlength="6" autocomplete="new-password" required></label>
      <label class="check"><input name="admin" type="checkbox"> Admin</label>
      <button class="chip" type="submit">Add user</button>
    </form>
  </div>

  <div class="sgroup" id="lights-group">
    <h2>Lights</h2>
    <p class="hint" id="lights-note"></p>
    <div class="row" id="lights-mode"></div>
    <form class="sform" id="lights-form">
      <label>Device ID <input name="device_id" autocomplete="off" required></label>
      <label>Plug IP address <input name="ip" inputmode="decimal" autocomplete="off" required></label>
      <label>Local key <input name="local_key" type="password" maxlength="16" autocomplete="off"></label>
      <label>Protocol <select name="version"><option>3.1</option><option>3.2</option><option>3.3</option><option>3.4</option><option>3.5</option></select></label>
      <label>Off after no board activity, min <input name="idle_minutes" type="number" min="1" max="240" required></label>
      <label>Off after no new score, min <input name="no_score_minutes" type="number" min="1" max="240" required></label>
      <button class="chip" type="submit">Save lights</button>
    </form>
  </div>

  <div class="sgroup">
    <h2>Game lock</h2>
    <form class="sform" id="lock-form">
      <label>Release an unused lock after, hours <input name="hours" type="number" min="1" max="48" required></label>
      <button class="chip" type="submit">Save</button>
    </form>
  </div>
</section>

<!-- Game -->
<section id="game" class="screen" aria-label="Scoreboard">
  <div class="bar">
    <span class="dot" id="conn-dot" aria-hidden="true"></span>
    <span id="conn-text">Connecting to board</span>
    <span class="grow" id="match-text"></span>
    <button id="btn-reset" class="reset">Reset board</button>
    <button id="btn-passive">Passive view</button>
    <button id="btn-fix">Fix scores</button>
    <button id="btn-undo">Undo visit</button>
    <button id="btn-next">Next player</button>
    <button id="btn-menu">End game</button>
  </div>
  <div class="arena">
    <div class="players" id="players"></div>
    <aside class="boardview" aria-label="Hits this round">
      <svg id="board" viewBox="-1.12 -1.12 2.24 2.24" role="img" aria-label="Dartboard with this round's hits"></svg>
      <div class="side">
        <div class="cap" id="board-cap">This round</div>
        <div class="legend" id="legend"></div>
      </div>
    </aside>
  </div>
  <div class="visit">
    <button class="dart" data-i="0" aria-label="Dart 1, tap to correct">–</button>
    <button class="dart" data-i="1" aria-label="Dart 2, tap to correct">–</button>
    <button class="dart" data-i="2" aria-label="Dart 3, tap to correct">–</button>
    <div class="total"><b id="visit-total">0</b><span id="visit-note">this visit</span></div>
  </div>
</section>

<!-- Passive display: board, hits and recent scores only -->
<section id="passive" class="screen" aria-label="Passive scoreboard">
  <div class="pbar"><span id="p-title">Waiting for a game</span><span class="grow"></span><span id="p-lock"></span><span id="p-stamp"></span><button id="p-unlock" hidden>Force unlock</button><button id="p-exit">Exit</button></div>
  <div class="pmain">
    <div class="pboard">
      <svg id="p-board" viewBox="-1.12 -1.12 2.24 2.24" role="img" aria-label="Dartboard with this round's hits"></svg>
      <div class="pcap" id="p-cap"></div>
      <div class="phits" id="p-hits"></div>
    </div>
    <div class="pplayers" id="p-players"></div>
  </div>
</section>

<div class="banner" id="banner" role="dialog" aria-modal="true" aria-labelledby="banner-title">
  <div>
    <h2 id="banner-title"></h2>
    <p id="banner-text"></p>
    <div class="row" id="banner-actions"></div>
  </div>
</div>

<div class="pad" id="pad" role="dialog" aria-modal="true" aria-label="Correct dart">
  <div class="sheet">
    <div class="mult" id="pad-mult"></div>
    <div class="nums" id="pad-nums"></div>
    <div class="foot">
      <button id="pad-clear" style="padding:0 18px">Use detected dart</button>
      <button id="pad-close" style="padding:0 18px">Cancel</button>
    </div>
  </div>
</div>

<div class="pad" id="fix" role="dialog" aria-modal="true" aria-label="Fix scores">
  <div class="sheet">
    <h3>Fix scores</h3>
    <p>Tap a dart to change it. Everything after it is recalculated.</p>
    <div id="fix-list"></div>
    <div class="foot"><button id="fix-close" style="padding:0 18px">Close</button></div>
  </div>
</div>

<pre class="raw" id="raw" aria-live="off"></pre>

<script>
'use strict';
// Served under a path (the internet link's /play): keep a trailing slash so relative URLs stay below it.
if (!/\/$|\.html$/.test(location.pathname)) location.replace(location.pathname + '/' + location.search + location.hash);
// ================= storage & helpers =================
const store = {
  get(k, d) { try { const v = localStorage.getItem('hdarts.' + k); return v == null ? d : JSON.parse(v); } catch { return d; } },
  set(k, v) { try { localStorage.setItem('hdarts.' + k, JSON.stringify(v)); } catch {} },
};
const $ = (id) => document.getElementById(id);
const clone = (o) => JSON.parse(JSON.stringify(o));
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

// ================= darts maths =================
function seg(n, m) {
  if (!m || !n) return { n: 0, m: 0, name: 'Miss' };
  if (n === 25) return { n, m, name: m === 2 ? 'Bull' : '25' };
  return { n, m, name: (m === 3 ? 'T' : m === 2 ? 'D' : 'S') + n };
}
function fromApi(t) {
  const s = t && t.segment;
  if (!s || t.bouncer) return seg(0, 0);
  const d = seg(Number(s.number) || 0, Number(s.multiplier) || 0);
  if (t.coords && isFinite(t.coords.x) && isFinite(t.coords.y)) { d.x = t.coords.x; d.y = t.coords.y; }
  return d;
}
// Board geometry, in units of the outer double radius (170 mm), y pointing up.
const ORDER = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5];
const R = { bull: 6.35 / 170, outerBull: 15.9 / 170, trebleIn: 99 / 170, trebleOut: 107 / 170, doubleIn: 162 / 170, doubleOut: 1 };
function dartPos(d) {
  if (isFinite(d.x) && isFinite(d.y)) return { x: d.x, y: d.y, exact: true };
  if (!d.m || !d.n) return null;
  if (d.n === 25) return { x: 0, y: d.m === 2 ? 0 : -(R.bull + R.outerBull) / 2 };
  const r = d.m === 3 ? (R.trebleIn + R.trebleOut) / 2 : d.m === 2 ? (R.doubleIn + R.doubleOut) / 2 : (R.trebleOut + R.doubleIn) / 2;
  const a = (90 - ORDER.indexOf(d.n) * 18) * Math.PI / 180;
  return { x: r * Math.cos(a), y: r * Math.sin(a) };
}
const value = (d) => d.n * d.m;

const FINISH = [20, 16, 18, 12, 10, 8, 19, 17, 15, 14, 13, 11, 9, 7, 6, 5, 4, 3, 2, 1].map((n) => seg(n, 2)).concat([seg(25, 2)]);
const SETUP = [];
for (let n = 20; n >= 1; n--) SETUP.push(seg(n, 3));
SETUP.push(seg(25, 1), seg(25, 2));
for (let n = 20; n >= 1; n--) SETUP.push(seg(n, 1));
const oneDart = (r) => FINISH.find((d) => value(d) === r) || null;
function twoDarts(r) {
  for (const f of FINISH) {
    const need = r - value(f);
    if (need <= 0) continue;
    const a = SETUP.find((d) => value(d) === need);
    if (a) return [a, f];
  }
  return null;
}
function checkout(r, dartsLeft) {
  if (r > 170 || r < 2) return null;
  if (dartsLeft >= 1 && oneDart(r)) return [oneDart(r)];
  if (dartsLeft >= 2) { const two = twoDarts(r); if (two) return two; }
  if (dartsLeft >= 3) {
    for (const a of SETUP) {
      const rest = r - value(a);
      if (rest < 2) continue;
      const tail = oneDart(rest) ? [oneDart(rest)] : twoDarts(rest);
      if (tail) return [a, ...tail];
    }
  }
  return null;
}
const argmax = (arr) => { let best = -Infinity, idx = [], i = 0; for (const v of arr) { if (v > best) { best = v; idx = [i]; } else if (v === best) idx.push(i); i++; } return idx; };
const argmin = (arr) => argmax(arr.map((v) => -v));

// ================= throw tips =================
// Suggestions for the player at the board, shown under their score. Per device: menu "Throw tips".
const tipsOn = () => store.get('tips', true);
const GOOD_LEAVES = [40, 32, 36, 16, 24, 20, 8, 12, 28, 50];   // leaves that finish on a favourite double
const BOGEY = new Set([169, 168, 166, 165, 163, 162, 159]);    // no three-dart finish
const SINGLES = [...Array.from({ length: 20 }, (_, k) => seg(20 - k, 1)), seg(25, 1)];
const TREBLES_FIRST = [seg(20, 3), seg(19, 3), seg(18, 3), seg(17, 3), ...SINGLES];
// X01 when no finish is possible with the darts left: score, or set up a good finish.
// Tips are recalculated after every dart, so they only plan the next dart.
const TREBLES = Array.from({ length: 20 }, (_, k) => seg(20 - k, 3));
function x01Tip(r, dartsLeft) {
  if (r > 170) {
    // Score heavily, but don't leave a number that has no finish.
    for (const t of [20, 19, 18]) { const leave = r - 3 * t; if (leave > 170 || !BOGEY.has(leave)) return `Aim T${t}`; }
    return 'Aim T20';
  }
  const leaveWith = (darts, n) => darts.find((a) => value(a) === r - n);
  const doubles = GOOD_LEAVES.filter((n) => n !== 50);
  let a = null, left = 0;
  // 1. a single that leaves a favourite double, 2. a treble that does, 3. any single that leaves a
  // one-dart finish (biggest double first), 4. a two-dart finish, 5. just not a dead number.
  for (const list of [SINGLES, TREBLES]) {
    for (const n of doubles) { const d = leaveWith(list, n); if (d) { a = d; left = n; break; } }
    if (a) break;
  }
  if (!a) for (const d of [...SINGLES].reverse()) { const n = r - value(d); if (n >= 2 && oneDart(n)) { a = d; left = n; break; } }
  if (!a) for (const d of TREBLES_FIRST) { const n = r - value(d); if (n >= 2 && n <= 110 && twoDarts(n)) { a = d; left = n; break; } }
  if (!a) for (const d of TREBLES_FIRST) { const n = r - value(d); if (n >= 2 && !BOGEY.has(n)) { a = d; left = n; break; } }
  if (!a) return 'Aim T20';
  const d = oneDart(left);
  return `Set up ${a.name}, leaves ${left}${d ? ' (' + d.name + ')' : ''}`;
}
// X01 straight out: any dart that reaches zero, else score.
function straightOutTip(r) {
  const all = [seg(25, 2), seg(25, 1), ...[3, 2, 1].flatMap((m) => Array.from({ length: 20 }, (_, k) => seg(20 - k, m)))];
  const one = all.find((d) => value(d) === r);
  return one ? `Finish ${one.name}` : r > 60 ? 'Aim T20' : `Aim ${r > 40 ? 'T' + Math.min(20, Math.floor(r / 3)) : 'S' + Math.min(20, r)}`;
}
// Cricket: score when it helps, close what opponents score on, else close the highest open number.
function cricketTip(s, i) {
  const me = s.p[i], others = s.p.filter((p, j) => j !== i), mode = s.o.mode;
  const open = (p, t) => p.marks[t] < 3;
  const aim = (t, why) => `Aim ${t === 25 ? 'Bull' : 'T' + t} · ${why}`;
  if (mode !== 'none' && others.length) {
    const pts = others.map((p) => p.pts);
    const needPoints = mode === 'standard' ? me.pts <= Math.max(...pts) : me.pts >= Math.min(...pts);
    const scoreOn = CRICKET.find((t) => !open(me, t) && others.some((p) => open(p, t)));
    if (needPoints && scoreOn) return aim(scoreOn, mode === 'standard' ? 'score' : 'points to opponents');
    const defend = CRICKET.find((t) => open(me, t) && others.some((p) => !open(p, t)));
    if (defend) return aim(defend, 'close it');
  }
  const next = CRICKET.find((t) => open(me, t));
  return next ? aim(next, 'close it') : '';
}
// Killer: become a killer, then go after the weakest opponent.
function killerTip(s, i) {
  const me = s.p[i];
  if (me.lives <= 0) return '';
  if (!me.killer) return `Aim D${me.num} to become a killer`;
  const foes = s.p.map((p, j) => ({ p, j })).filter(({ p, j }) => j !== i && p.lives > 0)
    .sort((a, b) => a.p.lives - b.p.lives || Number(b.p.killer) - Number(a.p.killer));
  if (!foes.length) return '';
  const name = G && G.cfg.players[foes[0].j] ? ` (${G.cfg.players[foes[0].j]})` : '';
  return `Aim D${foes[0].p.num}${name}`;
}

// ================= games =================
// Each game:  create(opts, n, prev) -> state
//             play(state, i, darts, ctx) -> { s, stop, won, winner, bust, scored, call }
//               ctx = { round, final }  (final = the visit is being committed)
//             view(state, i, ctx) -> { big, hint, extra, stats, tag }
//             roundEnd(state, round) -> winner index or null    (optional)
//             isOut(state, i) -> bool                           (optional)
const GAMES = {};

// ---------- X01 ----------
GAMES.x01 = {
  name: 'X01',
  rule: 'Count down to exactly zero. With double out the last dart must be a double.',
  options: [
    { key: 'start', label: 'Start', choices: [['301', 301], ['501', 501], ['701', 701]], def: 501 },
    { key: 'in', label: 'Start with', choices: [['Straight in', 'straight'], ['Double in', 'double']], def: 'straight' },
    { key: 'out', label: 'Finish', choices: [['Double out', 'double'], ['Straight out', 'straight']], def: 'double' },
  ],
  title: (o) => `${o.start}${o.in === 'double' ? ' double in' : ''}${o.out === 'double' ? '' : ' straight out'}`,
  create(o, n, prev) {
    return { o, p: Array.from({ length: n }, (_, i) => ({
      rem: o.start, open: o.in !== 'double', legDarts: 0,
      pts: prev ? prev.p[i].pts : 0, darts: prev ? prev.p[i].darts : 0,
      best: prev ? prev.p[i].best : 0, maxes: prev ? prev.p[i].maxes : 0,
    })) };
  },
  play(s, i, darts) {
    const p = s.p[i], dout = s.o.out === 'double';
    const start = p.rem;
    let rem = start, open = p.open, used = 0;
    for (const d of darts) {
      used++;
      if (!open) { if (d.m === 2) open = true; else continue; }
      const r = rem - value(d);
      if (r < 0 || (dout && r === 1) || (r === 0 && dout && d.m !== 2)) {
        return { s, stop: true, bust: true, scored: 0, call: 'Bust', commitDarts: 3 };
      }
      rem = r;
      if (rem === 0) {
        const scored = start;
        Object.assign(p, { rem: 0, open, legDarts: p.legDarts + used, pts: p.pts + scored, darts: p.darts + used, best: Math.max(p.best, scored) });
        return { s, stop: true, won: true, scored, call: 'Game shot' };
      }
    }
    const scored = start - rem;
    Object.assign(p, { rem, open, legDarts: p.legDarts + 3, pts: p.pts + scored, darts: p.darts + 3, best: Math.max(p.best, scored), maxes: p.maxes + (scored === 180 ? 1 : 0) });
    return { s, scored, call: scored === 0 ? 'No score' : scored === 180 ? 'One hundred and eighty!' : String(scored) };
  },
  view(s, i, ctx) {
    const p = s.p[i];
    const dl = ctx.active ? ctx.dartsLeft : 3;
    const route = s.o.out === 'double' && p.open && !ctx.bust ? checkout(p.rem, dl) : null;
    const tip = ctx.active && !ctx.bust && tipsOn() && dl > 0
      ? (!p.open ? ' · aim D20' : route ? '' : s.o.out === 'double' ? x01Tip(p.rem, dl) : straightOutTip(p.rem)) : '';
    return {
      big: p.rem,
      hint: ctx.bust ? 'Bust' : !p.open ? 'Needs a double to start' + tip : route ? route.map((d) => d.name).join(' ') : tip,
      stats: `Avg ${p.darts ? (p.pts / p.darts * 3).toFixed(1) : '–'} · Darts ${p.legDarts}${p.maxes ? ' · 180s ' + p.maxes : ''}`,
    };
  },
};

// ---------- Cricket ----------
const CRICKET = [20, 19, 18, 17, 16, 15, 25];
const markGlyph = (m) => ['', '/', 'X', 'Ⓧ'][Math.min(m, 3)];
GAMES.cricket = {
  name: 'Cricket',
  rule: 'Close 15 to 20 and the bull with three marks each. Score on numbers you have closed and others have not. Close everything with the most points to win.',
  options: [
    { key: 'mode', label: 'Scoring', choices: [['Standard', 'standard'], ['Cut-throat', 'cut'], ['No points', 'none']], def: 'standard' },
  ],
  title: (o) => ({ standard: 'Cricket', cut: 'Cut-throat cricket', none: 'Cricket, no points' }[o.mode]),
  create(o, n, prev) {
    return { o, p: Array.from({ length: n }, (_, i) => ({
      marks: Object.fromEntries(CRICKET.map((t) => [t, 0])), pts: 0,
      totalMarks: prev ? prev.p[i].totalMarks : 0, rounds: prev ? prev.p[i].rounds : 0,
    })) };
  },
  play(s, i, darts) {
    const me = s.p[i], mode = s.o.mode;
    let marks = 0;
    const closedAll = (p) => CRICKET.every((t) => p.marks[t] >= 3);
    for (const d of darts) {
      if (!CRICKET.includes(d.n) || !d.m) continue;
      for (let k = 0; k < d.m; k++) {
        marks++;
        if (me.marks[d.n] < 3) { me.marks[d.n]++; continue; }
        const val = d.n;
        const open = s.p.filter((p, j) => j !== i && p.marks[d.n] < 3);
        if (!open.length || mode === 'none') continue;
        if (mode === 'standard') me.pts += val;
        else open.forEach((p) => { p.pts += val; });
      }
      if (closedAll(me)) {
        const others = s.p.filter((p, j) => j !== i).map((p) => p.pts);
        const ok = mode === 'none' || !others.length ||
          (mode === 'standard' ? me.pts >= Math.max(...others) : me.pts <= Math.min(...others));
        if (ok) { me.totalMarks += marks; me.rounds++; return { s, stop: true, won: true, scored: marks, call: 'Game shot' }; }
      }
    }
    me.totalMarks += marks; me.rounds++;
    return { s, scored: marks, call: marks ? `${marks} mark${marks > 1 ? 's' : ''}` : 'No score' };
  },
  view(s, i, ctx) {
    const p = s.p[i];
    const rows = CRICKET.map((t) => `<span class="mk"><span class="t">${t === 25 ? 'Bull' : t}</span><span class="m${p.marks[t] >= 3 ? ' closed' : ''}">${markGlyph(p.marks[t])}</span></span>`).join('');
    return {
      big: s.o.mode === 'none' ? CRICKET.filter((t) => p.marks[t] >= 3).length + '/7' : p.pts,
      hint: ctx && ctx.active && tipsOn() ? cricketTip(s, i) : '',
      extra: `<div class="marks">${rows}</div>`,
      stats: `Marks per round ${p.rounds ? (p.totalMarks / p.rounds).toFixed(2) : '–'}`,
    };
  },
};

// ---------- Around the Clock ----------
const CLOCK = [...Array.from({ length: 20 }, (_, k) => k + 1), 25];
GAMES.clock = {
  name: 'Around the Clock',
  rule: 'Hit 1 to 20 in order, then the bull. First to hit the bull wins.',
  options: [
    { key: 'hit', label: 'Counts as a hit', choices: [['Any segment', 'any'], ['Doubles only', 'double'], ['Trebles only', 'treble']], def: 'any' },
    { key: 'skip', label: 'Doubles and trebles', choices: [['Advance one', false], ['Skip ahead', true]], def: false },
  ],
  title: (o) => 'Around the Clock' + (o.hit === 'any' ? '' : o.hit === 'double' ? ', doubles' : ', trebles'),
  create(o, n) { return { o, p: Array.from({ length: n }, () => ({ k: 0, darts: 0 })) }; },
  play(s, i, darts) {
    const p = s.p[i], o = s.o;
    let adv = 0, used = 0;
    for (const d of darts) {
      used++;
      const target = CLOCK[p.k];
      if (d.n !== target || !d.m) continue;
      const ok = target === 25 ? (o.hit !== 'double' || d.m === 2) : o.hit === 'any' || (o.hit === 'double' && d.m === 2) || (o.hit === 'treble' && d.m === 3);
      if (!ok) continue;
      const step = o.skip && target !== 25 ? d.m : 1;
      p.k = Math.min(p.k + step, 20);
      adv += step;
      if (target === 25) { p.darts += used; return { s, stop: true, won: true, scored: adv, call: 'Game shot' }; }
    }
    p.darts += 3;
    return { s, scored: adv, call: adv ? `${adv} hit${adv > 1 ? 's' : ''}` : 'No score' };
  },
  view(s, i, ctx) {
    const p = s.p[i], o = s.o;
    const t = CLOCK[p.k];
    let tip = '';
    if (ctx && ctx.active && tipsOn()) {
      tip = t === 25 ? (o.hit === 'double' ? 'Aim Bull (inner)' : 'Aim Bull')
        : o.hit === 'double' ? `Aim D${t}` : o.hit === 'treble' ? `Aim T${t}`
        : o.skip ? `Aim T${t} (moves 3)` : `Aim ${t} (big single)`;
    }
    return { big: t === 25 ? 'Bull' : t, hint: tip ? `${tip} · ${p.k} of 21 done` : `${p.k} of 21 done`, stats: `Darts ${p.darts}` };
  },
};

// ---------- Shanghai ----------
GAMES.shanghai = {
  name: 'Shanghai',
  rule: 'Round 1 aims at 1, round 2 at 2, and so on. Only the round\'s number scores. A single, double and treble of it in one visit is a Shanghai and wins at once.',
  options: [{ key: 'rounds', label: 'Rounds', choices: [['7 rounds', 7], ['10 rounds', 10], ['20 rounds', 20]], def: 7 }],
  title: (o) => `Shanghai, ${o.rounds} rounds`,
  rounds: (o) => o.rounds,
  create(o, n) { return { o, p: Array.from({ length: n }, () => ({ pts: 0 })) }; },
  target: (round) => ((round - 1) % 20) + 1,
  play(s, i, darts, ctx) {
    const t = this.target(ctx.round);
    const p = s.p[i];
    let scored = 0; const kinds = new Set();
    for (const d of darts) if (d.n === t) { scored += value(d); kinds.add(d.m); }
    p.pts += scored;
    if (kinds.size === 3) return { s, stop: true, won: true, scored, call: 'Shanghai!' };
    return { s, scored, call: scored ? String(scored) : 'No score' };
  },
  view(s, i, ctx) {
    const t = this.target(ctx.round);
    return { big: s.p[i].pts, hint: ctx.active ? (tipsOn() ? `Aim T${t} · S, D and T of ${t} = Shanghai` : `Aim at ${t}`) : '', stats: '' };
  },
  roundEnd(s, round) {
    if (round < s.o.rounds) return null;
    const w = argmax(s.p.map((p) => p.pts));
    return w.length === 1 ? w[0] : null; // tie: keep playing extra rounds
  },
};

// ---------- Count-Up ----------
GAMES.countup = {
  name: 'Count-Up',
  rule: 'Score as many points as you can in a set number of rounds. Highest total wins.',
  options: [{ key: 'rounds', label: 'Rounds', choices: [['7 rounds', 7], ['8 rounds', 8], ['10 rounds', 10]], def: 8 }],
  title: (o) => `Count-Up, ${o.rounds} rounds`,
  rounds: (o) => o.rounds,
  create(o, n) { return { o, p: Array.from({ length: n }, () => ({ pts: 0, darts: 0 })) }; },
  play(s, i, darts) {
    const scored = darts.reduce((a, d) => a + value(d), 0);
    s.p[i].pts += scored; s.p[i].darts += 3;
    return { s, scored, call: scored === 180 ? 'One hundred and eighty!' : scored ? String(scored) : 'No score' };
  },
  view(s, i, ctx) {
    const p = s.p[i];
    return { big: p.pts, hint: ctx && ctx.active && tipsOn() ? 'Aim T20' : '', stats: `Avg ${p.darts ? (p.pts / p.darts * 3).toFixed(1) : '–'}` };
  },
  roundEnd(s, round) {
    if (round < s.o.rounds) return null;
    const w = argmax(s.p.map((p) => p.pts));
    return w.length === 1 ? w[0] : null;
  },
};

// ---------- Halve-It ----------
const HALVE = [
  { label: '20', hit: (d) => d.n === 20 }, { label: '19', hit: (d) => d.n === 19 },
  { label: 'Any double', hit: (d) => d.m === 2 }, { label: '18', hit: (d) => d.n === 18 },
  { label: '17', hit: (d) => d.n === 17 }, { label: 'Any treble', hit: (d) => d.m === 3 },
  { label: '16', hit: (d) => d.n === 16 }, { label: '15', hit: (d) => d.n === 15 },
  { label: 'Bull', hit: (d) => d.n === 25 },
];
GAMES.halve = {
  name: 'Halve-It',
  rule: 'Each round has a target. Hits score their value. Miss the target with all three darts and your total is halved. Highest total after nine rounds wins.',
  options: [{ key: 'startPts', label: 'Starting points', choices: [['40', 40], ['0', 0]], def: 40 }],
  title: () => 'Halve-It',
  rounds: () => HALVE.length,
  target: (round) => HALVE[Math.min(round, HALVE.length) - 1],
  create(o, n) { return { o, p: Array.from({ length: n }, () => ({ pts: o.startPts })) }; },
  play(s, i, darts, ctx) {
    const t = this.target(ctx.round), p = s.p[i];
    const scored = darts.filter((d) => d.m && t.hit(d)).reduce((a, d) => a + value(d), 0);
    if (scored) { p.pts += scored; return { s, scored, call: String(scored) }; }
    if (ctx.final) { p.pts = Math.floor(p.pts / 2); return { s, scored: 0, call: 'Halved' }; }
    return { s, scored: 0 };
  },
  view(s, i, ctx) {
    const t = this.target(ctx.round);
    const best = { 'Any double': 'D20', 'Any treble': 'T20', Bull: 'Bull' }[t.label] || 'T' + t.label;
    return { big: s.p[i].pts, hint: ctx.active ? (tipsOn() ? `${t.label}: aim ${best} · a miss halves` : `Aim at ${t.label}`) : '' };
  },
  roundEnd(s, round) {
    if (round < HALVE.length) return null;
    const w = argmax(s.p.map((p) => p.pts));
    return w.length === 1 ? w[0] : null;
  },
};

// ---------- Bob's 27 ----------
const BOBS = [...Array.from({ length: 20 }, (_, k) => k + 1), 25];
GAMES.bobs = {
  name: "Bob's 27",
  rule: 'Doubles practice. Start on 27 and aim at D1, D2 … D20, then the bull. Each hit adds the double. Miss all three and you lose it. Drop to zero or below and you are out.',
  options: [],
  title: () => "Bob's 27",
  rounds: () => BOBS.length,
  target: (round) => BOBS[Math.min(round, BOBS.length) - 1],
  create(o, n) { return { o, p: Array.from({ length: n }, () => ({ pts: 27, out: false })) }; },
  play(s, i, darts, ctx) {
    const t = this.target(ctx.round), p = s.p[i];
    const hits = darts.filter((d) => d.n === t && d.m === 2).length;
    if (hits) { p.pts += hits * 2 * t; return { s, scored: hits * 2 * t, call: `${hits} hit${hits > 1 ? 's' : ''}` }; }
    if (ctx.final) { p.pts -= 2 * t; if (p.pts <= 0) p.out = true; return { s, scored: -2 * t, call: p.out ? 'Out' : 'Missed' }; }
    return { s, scored: 0 };
  },
  isOut: (s, i) => s.p[i].out,
  view(s, i, ctx) {
    const t = this.target(ctx.round);
    return { big: s.p[i].pts, hint: ctx.active ? `Aim at ${t === 25 ? 'Bull' : 'D' + t}` : '', tag: s.p[i].out ? 'Out' : '' };
  },
  roundEnd(s, round) {
    const alive = s.p.map((p, i) => i).filter((i) => !s.p[i].out);
    if (round < BOBS.length && alive.length > (s.p.length > 1 ? 1 : 0)) return null;
    const w = argmax(s.p.map((p) => p.pts));
    return w[0];
  },
};

// ---------- Killer ----------
GAMES.killer = {
  name: 'Killer',
  rule: 'Everyone gets a number. Hit your own double to become a killer, then hit other players\' doubles to take their lives. Hitting your own double as a killer costs you a life. Last player standing wins.',
  options: [
    { key: 'lives', label: 'Lives', choices: [['3 lives', 3], ['5 lives', 5]], def: 3 },
    { key: 'zone', label: 'Counts as a hit', choices: [['Doubles', 'double'], ['Any segment', 'any']], def: 'double' },
  ],
  title: (o) => `Killer, ${o.lives} lives`,
  minPlayers: 2,
  create(o, n) {
    const nums = Array.from({ length: 20 }, (_, k) => k + 1).sort(() => Math.random() - 0.5).slice(0, n);
    return { o, p: nums.map((num) => ({ num, lives: o.lives, killer: false })) };
  },
  play(s, i, darts) {
    const me = s.p[i];
    let call = '';
    for (const d of darts) {
      if (!d.m || (s.o.zone === 'double' && d.m !== 2)) continue;
      const owner = s.p.findIndex((p) => p.num === d.n && p.lives > 0);
      if (owner < 0) continue;
      if (owner === i) {
        if (!me.killer) { me.killer = true; call = 'Killer!'; } else { me.lives--; call = 'Ouch'; }
      } else if (me.killer) { s.p[owner].lives--; call = s.p[owner].lives <= 0 ? 'Killed' : 'Hit'; }
      const alive = s.p.map((p, k) => k).filter((k) => s.p[k].lives > 0);
      if (alive.length <= 1) return { s, stop: true, won: true, winner: alive[0] ?? i, scored: 0, call: 'Game shot' };
      if (me.lives <= 0) return { s, stop: true, scored: 0, call: 'Out' };
    }
    return { s, scored: 0, call: call || 'No score' };
  },
  isOut: (s, i) => s.p[i].lives <= 0,
  view(s, i, ctx) {
    const p = s.p[i];
    const tip = ctx && ctx.active && tipsOn() ? killerTip(s, i) : '';
    return { big: p.num, hint: '●'.repeat(Math.max(p.lives, 0)) + '○'.repeat(Math.max(s.o.lives - Math.max(p.lives, 0), 0)) + (tip ? ' · ' + tip : ''), tag: p.lives <= 0 ? 'Out' : p.killer ? 'Killer' : '', stats: `Lives ${Math.max(p.lives, 0)}` };
  },
};

// Short rules shown in the menu's Rules section. Keep in step with the play() functions above.
const RULES = {
  x01: [
    'Everyone starts from <b>301, 501 or 701</b> and subtracts the score of every dart.',
    'Finish on <b>exactly zero</b>. With <b>Double out</b> the last dart must be a double; the bull\'s-eye counts as one.',
    '<b>Bust</b>: going below zero, leaving 1, or reaching zero without a double (double out). The whole visit scores nothing.',
    '<b>Double in</b>: your darts only start counting after you hit a double.',
    'When a finish is possible the suggested checkout is shown under your score.',
  ],
  cricket: [
    'Numbers <b>15 to 20 and the bull</b>. A single is 1 mark, a double 2, a treble 3. Three marks close a number.',
    '<b>Standard</b>: once you have closed a number, hits on it score its value while any opponent still has it open.',
    '<b>Cut-throat</b>: those points go to the opponents who still have it open, and the <b>lowest</b> score wins.',
    '<b>No points</b>: just close all seven first.',
    'Close all seven while level or ahead on points (behind in cut-throat) to win the leg.',
  ],
  clock: [
    'Hit <b>1, 2, 3 … 20</b> in order, then the <b>bull</b>. First to hit the bull wins the leg.',
    '<b>Counts as a hit</b>: any segment of the number, doubles only, or trebles only (doubles only needs the bull\'s-eye at the end).',
    '<b>Skip ahead</b>: a double moves you on two numbers and a treble three. With Advance one every hit moves one.',
  ],
  shanghai: [
    'Round 1 aims at <b>1</b>, round 2 at <b>2</b>, and so on, for 7, 10 or 20 rounds.',
    'Only the round\'s number scores: single ×1, double ×2, treble ×3.',
    'A <b>single, double and treble</b> of the number in one visit is a <b>Shanghai</b> and wins at once.',
    'Otherwise the highest total after the last round wins. A tie plays extra rounds.',
  ],
  countup: [
    'Every dart scores its full value. Play <b>7, 8 or 10 rounds</b>.',
    'Highest total wins. A tie plays extra rounds.',
  ],
  halve: [
    'Nine rounds with a target each: <b>20, 19, any double, 18, 17, any treble, 16, 15, bull</b>.',
    'Darts that hit the target score their value.',
    'Miss the target with all three darts and your total is <b>halved</b> (rounded down).',
    'Start on <b>40 or 0</b> points. Highest total wins; a tie plays extra rounds on the bull.',
  ],
  bobs: [
    'Doubles practice. Start on <b>27</b> and aim at <b>D1, D2 … D20</b>, then the bull\'s-eye.',
    'Every hit on the round\'s double adds its value (D5 adds 10).',
    'Miss all three and that double\'s value is taken off.',
    'At <b>zero or below</b> you are out. Highest score at the end, or the last player left, wins.',
  ],
  killer: [
    'Every player gets a <b>random number</b>, shown as their big number.',
    'Hit <b>your own double</b> to become a <b>Killer</b> (any segment of it, if Counts as a hit is Any segment).',
    'As a Killer, hits on other players\' doubles take one of their <b>lives</b>. Hitting your own double costs you a life.',
    'Everyone starts with 3 or 5 lives. At zero you are out. <b>Last player standing</b> wins.',
  ],
};

const GAME_ORDER = ['x01', 'cricket', 'clock', 'shanghai', 'countup', 'halve', 'bobs', 'killer'];

// ================= engine =================
let G = null;
let api = { darts: [], status: '', lastSeen: 0, raw: null };
let ignoreUntilClear = false;
let saidForVisit = false;
let quiet = false, pendingWin = null;   // set while Fix scores replays visits
const mod = () => GAMES[G.cfg.game];
const emptyVisit = () => ({ overrides: {}, extra: [], seen: [] });

function newGame(cfg) {
  const g = { v: 2, hits: [], lastHits: [], cfg, legs: cfg.players.map(() => 0), cur: 0, legStarter: 0, leg: 1, round: 1, visit: emptyVisit(), history: [], over: false, winner: null };
  g.s = GAMES[cfg.game].create(cfg.opts, cfg.players.length, null);
  return g;
}
const isOut = (i) => !!(mod().isOut && mod().isOut(G.s, i));
const snapshot = () => clone(Object.assign({}, G, { history: [] }));

function detectedDarts() {
  if (ignoreUntilClear) return [];
  return (api.darts.length ? api.darts : (G.visit.seen || [])).slice(0, 3);
}
function visitDarts() {
  const all = detectedDarts().concat(G.visit.extra).slice(0, 3);
  for (const k of Object.keys(G.visit.overrides)) if (Number(k) < 3) all[Number(k)] = G.visit.overrides[k];
  return all.filter(Boolean);
}
function recentScores(i, n) {
  return G.history.filter((e) => e.fixScore != null && e.cur === i && e.leg === G.leg).slice(-n).map((e) => e.fixScore);
}
function preview(final) {
  const darts = visitDarts();
  const r = mod().play(clone(G.s), G.cur, darts, { round: G.round, final });
  r.darts = darts;
  return r;
}

function commitVisit() {
  if (!G || G.over) return;
  const r = preview(true);
  const snap = snapshot();
  snap.fixDarts = clone(r.darts);   // what this visit scored, for Fix scores
  snap.fixScore = r.bust ? 0 : (r.scored || 0);
  G.history.push(snap);
  if (G.history.length > 300) G.history.shift();
  G.s = r.s;
  G.hits = (G.hits || []).concat([{ p: G.cur, darts: r.darts }]);
  if (!saidForVisit && r.call) speak(r.call);
  saidForVisit = false;
  ignoreUntilClear = api.darts.length > 0;
  G.visit = emptyVisit();

  if (r.won) return legWon(r.winner ?? G.cur);

  // next player still in the game
  const n = G.cfg.players.length;
  const pos = (i) => (i - G.legStarter + n) % n;
  let next = G.cur, wrapped = false;
  for (let k = 0; k < n; k++) {
    const cand = (next + 1) % n;
    if (pos(cand) <= pos(next)) wrapped = true;
    next = cand;
    if (!isOut(next)) break;
  }
  if (wrapped) {
    if (mod().roundEnd) {
      const w = mod().roundEnd(G.s, G.round);
      if (w != null) return legWon(w);
    }
    G.round++;
    G.lastHits = G.hits; G.hits = [];
  }
  if (isOut(next) && mod().roundEnd) { const w = mod().roundEnd(G.s, Infinity); return legWon(w); }
  G.cur = next;
  save(); render();
}

function legWon(w) {
  G.legs[w]++;
  const name = G.cfg.players[w];
  if (G.legs[w] >= G.cfg.legsToWin) {
    G.over = true; G.winner = w;
    speak(`Game shot, and the match, ${name}`);
    save(); render();
    if (quiet) pendingWin = [true, name]; else showWin(true, name);
    releaseBoard();   // the match is over: others may play
    return;
  }
  speak(`Game shot, ${name}`);
  if (quiet) pendingWin = [false, name]; else showWin(false, name);
  G.leg++;
  G.legStarter = (G.legStarter + 1) % G.cfg.players.length;
  G.cur = G.legStarter; G.round = 1;
  G.lastHits = []; G.hits = [];
  G.s = mod().create(G.cfg.opts, G.cfg.players.length, G.s);
  G.visit = emptyVisit();
  save(); render();
}

function undo() {
  if (!G || !G.history.length) return;
  const hist = G.history;
  G = Object.assign(G.history.pop(), { history: hist });
  delete G.fixDarts; delete G.fixScore;
  const restored = (G.visit.seen || []).slice(0, 3).concat(G.visit.extra).slice(0, 3);
  Object.keys(G.visit.overrides).forEach((k) => { if (restored[k]) restored[k] = G.visit.overrides[k]; });
  G.visit = { overrides: {}, extra: restored, seen: [] };
  ignoreUntilClear = api.darts.length > 0;
  hideBanner(); save(); render();
}

// ================= board polling =================
function apiBase() { return store.get('api', `http://${location.hostname || 'localhost'}:3180`); }
// On an HTTPS page (the internet link) browsers block plain-http requests, so the board is read
// through the Pi (cgi-bin/board), which also checks the game lock before a reset.
const viaPi = () => location.protocol === 'https:';
async function poll() {
  try {
    const res = await fetch(viaPi() ? 'cgi-bin/board' : apiBase() + '/api/state', { cache: 'no-store' });
    const s = await res.json();
    api.raw = s;
    api.status = String(s.status || s.event || '');
    api.lastSeen = Date.now();
    const darts = Array.isArray(s.throws) ? s.throws.map(fromApi) : [];
    const changed = darts.length !== api.darts.length || darts.some((d, i) => d.name !== api.darts[i].name);
    api.darts = darts;
    if (darts.length === 0 && ignoreUntilClear) ignoreUntilClear = false;
    // Only the game on screen takes darts, and only for the user holding the board.
    const playing = $('game').classList.contains('on') || passiveMode === 'local';
    const mine = G && !G.over && !lockedByOther() && playing;
    if (mine && s.running === false && /stopped/i.test(api.status) && Date.now() - lastStartTry > 10000) startBoard();
    if (mine && !ignoreUntilClear && darts.length) G.visit.seen = darts.slice(0, 3);
    if (mine) onBoard(changed);
  } catch (e) {
    api.status = 'offline';
  }
  renderConn();
  if ($('raw').classList.contains('on')) $('raw').textContent = JSON.stringify(api.raw, null, 2);
}
function onBoard(changed) {
  const r = preview(false);
  if (r.won) { commitVisit(); return; }
  // The visit ends when the darts are pulled: the board clears its throws after takeout.
  if (!ignoreUntilClear && api.darts.length === 0 && (G.visit.seen || []).length) { commitVisit(); return; }
  if ((r.stop || r.darts.length === 3) && !saidForVisit) {
    const fin = preview(true);
    if (fin.call) speak(fin.call);
    saidForVisit = true;
  }
  if (changed) render();
}

// ================= caller =================
function speak(text) {
  if (quiet || !text || !store.get('voice', true) || !('speechSynthesis' in window)) return;
  try { const u = new SpeechSynthesisUtterance(text); u.rate = 0.95; speechSynthesis.cancel(); speechSynthesis.speak(u); } catch {}
}

// ================= rendering =================
function render() {
  if (!G) return;
  const r = preview(false);
  const shown = r.s;   // live state including the current visit
  const darts = r.darts;
  const wrap = $('players');
  wrap.innerHTML = '';
  G.cfg.players.forEach((name, i) => {
    const active = i === G.cur && !G.over;
    const v = mod().view(shown, i, { active, dartsLeft: 3 - darts.length, bust: active && r.bust, round: G.round });
    const el = document.createElement('div');
    el.className = 'player' + (active ? ' active' : '') + (active && r.bust ? ' bust' : '') + (isOut(i) && !active ? ' out' : '');
    el.innerHTML = `
      <div class="name">${esc(name)}</div>
      <div class="legs">Legs ${G.legs[i]}${v.tag ? ` <span class="tag">${esc(v.tag)}</span>` : ''}</div>
      <div class="score">${esc(v.big)}</div>
      <div class="route">${esc(v.hint || '')}</div>
      ${v.extra || ''}
      <div class="stats">${esc(v.stats || '')}</div>
      <div class="recent" aria-label="Last five visits">${recentScores(i, 5).map((n, k, a) => `<span${k === a.length - 1 ? ' class="new"' : ''}>${n}</span>`).join('')}</div>`;
    if (active) el.setAttribute('aria-current', 'true');
    wrap.appendChild(el);
  });
  const detected = detectedDarts().length;
  document.querySelectorAll('.dart').forEach((b) => {
    const i = Number(b.dataset.i), d = darts[i];
    b.textContent = d ? d.name : '–';
    b.classList.toggle('hit', !!d);
    b.classList.toggle('edited', !!d && (G.visit.overrides[i] != null || i >= detected));
  });
  $('visit-total').textContent = r.bust ? 0 : (r.scored || 0);
  $('visit-note').textContent = r.bust ? 'bust, pull the darts' : darts.length === 3 || r.stop ? 'pull the darts' : 'this visit';
  const rounds = mod().rounds ? mod().rounds(G.cfg.opts) : null;
  $('match-text').textContent = `${mod().title(G.cfg.opts)} · leg ${G.leg} · ${rounds ? `round ${G.round}/${rounds} · ` : ''}first to ${G.cfg.legsToWin}`;
  $('btn-undo').disabled = !G.history.length;
  $('btn-fix').disabled = !G.history.some((e) => e.fixDarts);
  renderBoard(darts);
  if (passiveMode === 'local') paintPassive(buildPayload());
  publish();
}

const PCOL = ['#2ef2ff', '#ff3dbb', '#a4ff3a', '#ffc23d', '#b58cff', '#ffffff', '#ff6a3d', '#3d8bff'];
let boardBase = '';
function boardSvg() {
  if (boardBase) return boardBase;
  const pt = (r, deg) => { const a = deg * Math.PI / 180; return `${(r * Math.cos(a)).toFixed(4)},${(-r * Math.sin(a)).toFixed(4)}`; };
  const wedge = (r1, r2, a1, a2, fill) => `<path d="M${pt(r1, a1)} L${pt(r2, a1)} A${r2},${r2} 0 0 1 ${pt(r2, a2)} L${pt(r1, a2)} A${r1},${r1} 0 0 0 ${pt(r1, a1)}Z" fill="${fill}"/>`;
  let out = `<defs><filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="0.018" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs><circle r="1.1" fill="#111111" stroke="#2a2a2a" stroke-width="0.006"/>`;
  let rings = '';
  ORDER.forEach((n, k) => {
    // wedge centred on 90 - k*18 degrees; outer arc runs clockwise on screen (sweep 1), inner arc back (sweep 0)
    const c = 90 - k * 18, a1 = c + 9, a2 = c - 9;
    const dark = k % 2 === 0;
    const single = dark ? '#151515' : '#f2e4bd', ring = dark ? '#d9242b' : '#1b8a3d';   // regular board colours
    out += wedge(R.outerBull, R.trebleIn, a1, a2, single) + wedge(R.trebleOut, R.doubleIn, a1, a2, single);
    rings += wedge(R.trebleIn, R.trebleOut, a1, a2, ring) + wedge(R.doubleIn, R.doubleOut, a1, a2, ring);
    const [lx, ly] = pt(1.06, c).split(',');
    out += `<text x="${lx}" y="${ly}" font-size="0.085" fill="#f2f2f2" text-anchor="middle" dominant-baseline="central" font-family="sans-serif">${n}</text>`;
  });
  out += `<g>${rings}<circle r="${R.outerBull}" fill="#1b8a3d"/><circle r="${R.bull}" fill="#d9242b"/></g>`;
  return (boardBase = out);
}
function dotsFor(sets, showLast) {
  let dots = '';
  sets.forEach((v) => {
    v.darts.forEach((d) => {
      const pos = dartPos(d);
      if (!pos) return;
      const col = PCOL[v.p % PCOL.length];
      const r = v.live ? 0.05 : 0.038;
      dots += `<circle cx="${pos.x.toFixed(4)}" cy="${(-pos.y).toFixed(4)}" r="${r}" fill="${col}" stroke="#04060d" stroke-width="0.012" filter="url(#glow)" opacity="${showLast ? 0.5 : 1}"/>`;
      if (v.live) dots += `<circle cx="${pos.x.toFixed(4)}" cy="${(-pos.y).toFixed(4)}" r="0.08" fill="none" stroke="${col}" stroke-width="0.012"/>`;
    });
  });
  return dots;
}
function hitSets(live) {
  const committed = (G.hits || []).length ? G.hits : null;
  const showLast = !committed && !live.length && (G.lastHits || []).length;
  const sets = (committed || (showLast ? G.lastHits : [])).slice();
  if (!G.over && live.length) sets.push({ p: G.cur, darts: live, live: true });
  return { sets, showLast };
}
function renderBoard(live) {
  const { sets, showLast } = hitSets(live);
  $('board').innerHTML = boardSvg() + dotsFor(sets, showLast);
  $('board-cap').textContent = showLast ? 'Last round' : `Round ${G.round} hits`;
  $('legend').innerHTML = G.cfg.players.map((n, i) => `<span><i style="background:${PCOL[i % PCOL.length]}"></i>${esc(n)}</span>`).join('');
}
function renderConn() {
  const dot = $('conn-dot'), txt = $('conn-text');
  if (!api.lastSeen || Date.now() - api.lastSeen > 4000) { dot.className = 'dot off'; txt.textContent = 'Board offline'; return; }
  const s = api.status;
  dot.className = 'dot ' + (/throw/i.test(s) ? 'ok' : 'wait');
  txt.textContent = /throw/i.test(s) ? 'Ready to throw' : /takeout/i.test(s) ? 'Pulling darts' : s || 'Connected';
}

// ================= banners =================
function showWin(match, name) {
  $('banner-title').textContent = match ? `${name} wins` : `Game shot, ${name}`;
  $('banner-text').textContent = match
    ? G.cfg.players.map((n, i) => `${n}: ${G.legs[i]} leg${G.legs[i] === 1 ? '' : 's'}`).join('  |  ')
    : 'Next leg is ready. Pull the darts.';
  const acts = $('banner-actions'); acts.innerHTML = '';
  const add = (label, fn) => { const b = document.createElement('button'); b.className = 'chip'; b.textContent = label; b.onclick = fn; acts.appendChild(b); };
  if (match) {
    add('Rematch', async () => { if (!(await takeBoard())) return; G = newGame(G.cfg); ignoreUntilClear = api.darts.length > 0; startBoard().then(resetBoard); pingLights(); hideBanner(); save(); render(); });
    add('New game', () => { hideBanner(); toSetup(); });
    add('Undo last visit', undoOwned);
  } else {
    add('Continue', hideBanner);
    add('Undo last visit', undo);
    setTimeout(() => { if (G && !G.over) hideBanner(); }, 4000);
  }
  $('banner').classList.add('on');
}
function hideBanner() { $('banner').classList.remove('on'); }

// ================= keypad =================
let padIndex = 0, padMult = 1, padFix = null;   // padFix: { idx, k } when editing an earlier visit
function openPad(i, fix) {
  padIndex = i; padMult = 1; padFix = fix || null;
  $('pad-clear').textContent = padFix ? 'Remove dart' : 'Use detected dart';
  $('pad-clear').hidden = !!padFix && padFix.k >= G.history[padFix.idx].fixDarts.length;
  const mult = $('pad-mult'); mult.innerHTML = '';
  [['Single', 1], ['Double', 2], ['Treble', 3]].forEach(([label, m]) => {
    const b = document.createElement('button'); b.textContent = label; b.setAttribute('aria-pressed', String(m === padMult));
    b.onclick = () => { padMult = m; mult.querySelectorAll('button').forEach((x, k) => x.setAttribute('aria-pressed', String(k + 1 === m))); };
    mult.appendChild(b);
  });
  const nums = $('pad-nums'); nums.innerHTML = '';
  const pick = (d) => {
    if (padFix) {
      const darts = G.history[padFix.idx].fixDarts.slice();
      darts[padFix.k] = d;
      $('pad').classList.remove('on');
      fixVisit(padFix.idx, darts);
      return;
    }
    const detected = detectedDarts().length;
    if (padIndex < detected) G.visit.overrides[padIndex] = d;
    else {
      const k = padIndex - detected;
      if (k < G.visit.extra.length) G.visit.extra[k] = d; else G.visit.extra.push(d);
    }
    saidForVisit = false;
    $('pad').classList.remove('on'); save(); render();
    if (preview(false).won) commitVisit();
  };
  for (let n = 1; n <= 20; n++) { const b = document.createElement('button'); b.textContent = n; b.onclick = () => pick(seg(n, padMult)); nums.appendChild(b); }
  const bull = document.createElement('button'); bull.textContent = 'Bull'; bull.onclick = () => pick(seg(25, padMult === 1 ? 1 : 2)); nums.appendChild(bull);
  const miss = document.createElement('button'); miss.textContent = 'Miss'; miss.onclick = () => pick(seg(0, 0)); nums.appendChild(miss);
  $('pad').classList.add('on');
}
$('pad-close').onclick = () => $('pad').classList.remove('on');
$('pad-clear').onclick = () => {
  if (padFix) {
    const darts = G.history[padFix.idx].fixDarts.slice();
    darts.splice(padFix.k, 1);
    $('pad').classList.remove('on');
    fixVisit(padFix.idx, darts);
    return;
  }
  delete G.visit.overrides[padIndex]; $('pad').classList.remove('on'); render(); };
// ================= fix scores =================
// Every committed visit keeps the darts it scored (history[i].fixDarts) and the game state
// before it. Fixing a dart restores that state and replays the visit and all later ones.
function fixVisit(idx, newDarts) {
  const h = G.history, backup = G, ig = ignoreUntilClear, live = G.visit;
  const keep = h.slice(0, idx);
  G = Object.assign(clone(h[idx]), { history: keep });
  delete G.fixDarts; delete G.fixScore;
  quiet = true; pendingWin = null;
  let ok = true;
  for (let k = 0; idx + k < h.length; k++) {
    const e = h[idx + k];
    if (k > 0 && (G.over || G.leg !== e.leg || G.cur !== e.cur)) { ok = false; break; }
    G.visit = { overrides: {}, extra: clone(k === 0 ? newDarts : e.fixDarts), seen: [] };
    ignoreUntilClear = true;
    commitVisit();
  }
  quiet = false;
  const win = pendingWin; pendingWin = null;
  if (!ok) {
    G = backup; ignoreUntilClear = ig;
    alert('That change would alter who wins a leg or whose turn it is later on, so it was not applied. Use Undo visit to step back further.');
    render(); return;
  }
  ignoreUntilClear = ig;
  saidForVisit = false;
  hideBanner();
  if (win) { $('fix').classList.remove('on'); showWin(win[0], win[1]); } else if (!G.over) G.visit = live;
  save(); render(); renderFix(idx);
}
function renderFix(flash) {
  const list = $('fix-list'); list.innerHTML = '';
  const rows = [];
  G.history.forEach((e, i) => { if (e.fixDarts) rows.push(i); });
  rows.reverse().slice(0, 30).forEach((i) => {
    const e = G.history[i];
    const row = document.createElement('div');
    row.className = 'frow' + (i === flash ? ' fixed' : '');
    const who = document.createElement('div'); who.className = 'who';
    who.innerHTML = `${esc(G.cfg.players[e.cur])}<small>Leg ${e.leg} · round ${e.round}</small>`;
    row.appendChild(who);
    if (e.fixScore != null) { const t = document.createElement('div'); t.className = 'pts'; t.textContent = e.fixScore; row.appendChild(t); }
    e.fixDarts.forEach((d, k) => {
      const b = document.createElement('button'); b.textContent = d.name; b.setAttribute('aria-label', `Dart ${k + 1}, ${d.name}, tap to change`);
      b.onclick = () => openPad(0, { idx: i, k });
      row.appendChild(b);
    });
    if (e.fixDarts.length < 3) {
      const b = document.createElement('button'); b.className = 'add'; b.textContent = '+'; b.setAttribute('aria-label', 'Add a dart');
      b.onclick = () => openPad(0, { idx: i, k: e.fixDarts.length });
      row.appendChild(b);
    }
    list.appendChild(row);
  });
  if (!rows.length) list.innerHTML = '<p>No visits yet.</p>';
}
$('btn-fix').onclick = async () => { if (!G) return; if (G.over && !(await takeBoard())) return; renderFix(); $('fix').classList.add('on'); };
$('fix-close').onclick = () => $('fix').classList.remove('on');
document.querySelectorAll('.dart').forEach((b) => b.onclick = () => G && !G.over && openPad(Number(b.dataset.i)));

// ================= passive display =================
// A display-only view: dartboard, this round's hits and the last 10 scores of each player.
// The device that scores publishes the game to the Pi (cgi-bin/game); a TV opened in passive mode
// (#passive) reads it from there. The "Passive view" button shows the local game the same way.
let passiveMode = null;       // null | 'local' | 'remote'
let passiveTimer = null;
let lastPublished = '', publishTimer = 0, publishedAt = 0;

function buildPayload() {
  const r = preview(false), darts = r.darts;
  const { sets, showLast } = hitSets(darts);
  return {
    title: mod().title(G.cfg.opts), leg: G.leg, legsToWin: G.cfg.legsToWin, round: G.round, over: G.over,
    winner: G.winner != null ? G.cfg.players[G.winner] : null, sets, showLast,
    players: G.cfg.players.map((name, i) => {
      const active = i === G.cur && !G.over;
      const v = mod().view(r.s, i, { active, dartsLeft: 3 - darts.length, bust: active && r.bust, round: G.round });
      return { name, legs: G.legs[i], big: v.big, hint: v.hint || '', tag: v.tag || '', active, bust: active && !!r.bust, out: isOut(i) && !active, recent: recentScores(i, 10) };
    }),
  };
}
function publish(force) {
  if (!G || passiveMode === 'remote' || lockedByOther()) return;
  const body = JSON.stringify(buildPayload());
  if (!force && body === lastPublished) return;
  const wait = 400 - (Date.now() - publishedAt);
  if (wait > 0 && !force) { if (!publishTimer) publishTimer = setTimeout(() => { publishTimer = 0; publish(); }, wait); return; }
  lastPublished = body; publishedAt = Date.now();
  try { fetch('cgi-bin/game', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(Object.assign(JSON.parse(body), { t: Date.now() })) }).catch(() => {}); } catch {}
}
function paintPassive(d) {
  if (!d || d.none || !d.players) {
    $('p-title').textContent = 'Waiting for a game'; $('p-players').innerHTML = ''; $('p-hits').innerHTML = '';
    $('p-board').innerHTML = boardSvg(); $('p-cap').textContent = ''; return;
  }
  $('p-title').textContent = `${d.title} · leg ${d.leg} · first to ${d.legsToWin}${d.over && d.winner ? ' · ' + d.winner + ' wins' : ''}`;
  $('p-stamp').textContent = d.t && passiveMode === 'remote' ? 'Updated ' + new Date(d.t).toLocaleTimeString() : '';
  $('p-board').innerHTML = boardSvg() + dotsFor(d.sets || [], d.showLast);
  $('p-cap').textContent = d.showLast ? 'Last round' : `Round ${d.round} hits`;
  $('p-hits').innerHTML = (d.sets || []).map((v) => {
    const c = PCOL[v.p % PCOL.length], who = d.players[v.p] ? d.players[v.p].name : '';
    return v.darts.length ? `<span style="color:${c};border-color:${c}" ${d.showLast ? 'class="old"' : ''}>${esc(who)} ${v.darts.map((x) => esc(x.name)).join(' ')}</span>` : '';
  }).join('');
  $('p-players').innerHTML = d.players.map((p, i) => `
    <div class="pp${p.active ? ' active' : ''}${p.bust ? ' bust' : ''}${p.out ? ' out' : ''}">
      <div class="nm"><i style="display:inline-block;width:.5em;height:.5em;border-radius:50%;margin-right:.4em;background:${PCOL[i % PCOL.length]}"></i>${esc(p.name)}<small>Legs ${esc(p.legs)}${p.tag ? ' · ' + esc(p.tag) : ''}</small></div>
      <div class="big">${esc(p.big)}</div>
      <div class="sub">${esc(p.hint)}</div>
      <div class="rec" aria-label="Last 10 scores">${(p.recent || []).map((n, k, a) => `<span${k === a.length - 1 ? ' class="new"' : ''}>${esc(n)}</span>`).join('')}</div>
    </div>`).join('');
}
async function pollPassive() {
  try {
    const res = await fetch('cgi-bin/game', { cache: 'no-store' });
    paintPassive(await res.json());
  } catch { $('p-stamp').textContent = 'Connection lost'; }
}
function showPassive(mode) {
  passiveMode = mode;
  $('p-exit').hidden = !!window.PUBLIC_VIEW || forcedView;
  $('setup').classList.remove('on'); $('game').classList.remove('on'); $('passive').classList.add('on');
  clearInterval(passiveTimer);
  if (mode === 'remote') { pollPassive(); passiveTimer = setInterval(pollPassive, 700); }
  else paintPassive(buildPayload());
  screenOn(true);
}
function exitPassive() {
  if (window.PUBLIC_VIEW) return;
  clearInterval(passiveTimer);
  const was = passiveMode; passiveMode = null;
  $('passive').classList.remove('on');
  if (location.hash === '#passive') history.replaceState(null, '', location.pathname + location.search);
  if (was === 'local' && G) toGame(); else toSetup(true);
}
$('btn-passive').onclick = () => { if (G) showPassive('local'); };
$('open-passive').onclick = () => { location.hash = '#passive'; showPassive('remote'); };
$('p-exit').onclick = exitPassive;

// ================= sign-in and game lock =================
// The Pi knows who signed in (browser sign-in). Starting a game locks the board to that user until the
// match ends or they end the game; everyone else gets the live game read-only. Without sign-in
// (no users set up) there is no owner and nothing is locked.
let me = { user: '', owner: '', admin: false };
let forcedView = false;
const lockedByOther = () => !!me.owner && me.owner !== me.user;
async function lockCall(action) {
  try {
    const res = await fetch('cgi-bin/lock', action ? { method: 'POST', body: action } : { cache: 'no-store' });
    if (!res.ok) return true;              // older Pi without the lock: behave as before
    const d = await res.json();
    me = { user: d.me || '', owner: d.owner || '', admin: !!d.admin };
    return d.ok !== false;
  } catch { return true; }
}
function applyLock() {
  if (window.PUBLIC_VIEW) return;
  if (lockedByOther()) {
    if (!forcedView) { forcedView = true; hideBanner(); $('pad').classList.remove('on'); $('fix').classList.remove('on'); showPassive('remote'); }
    $('p-lock').textContent = `${me.owner} is playing · view only`;
    $('p-unlock').hidden = !me.admin;
  } else {
    $('p-lock').textContent = ''; $('p-unlock').hidden = true;
    if (forcedView) { forcedView = false; exitPassive(); }
  }
  const w = $('who');
  $('who-line').hidden = !me.user;
  $('btn-settings').hidden = !!me.user && !me.admin;
  w.textContent = me.user ? `Signed in as ${me.user}${me.admin ? ' (admin)' : ''}${me.owner === me.user ? ' · the board is yours until the game ends' : ''}` : '';
}
async function lockWatch() { await lockCall(); applyLock(); }
// Sign out. Browsers keep a sign-in until the tab is closed and offer no way to drop it, so the page
// signs in once more with a name that doesn't exist: the browser replaces the saved sign-in with it
// and asks for a name and password on the next load.
async function signOut() {
  if (me.owner && me.owner === me.user && G && !G.over && !confirm('Sign out? Your game stays locked to you until it ends or an admin unlocks it.')) return;
  screenOn(false);
  await new Promise((done) => {
    const x = new XMLHttpRequest();
    x.open('GET', 'cgi-bin/lock?signout=' + Date.now(), true, 'signed-out', 'x' + Date.now());
    x.onloadend = done; x.send();
  });
  location.replace(location.pathname + '?signed-out=' + Date.now());
}
// Takes the board for this user; false (and the view-only screen) if someone else has it.
async function takeBoard() {
  const ok = await lockCall('acquire');
  applyLock();
  if (!ok && !lockedByOther()) alert('The board is in use by someone else.');
  return ok;
}
function releaseBoard() { lockCall('release').then(applyLock); }
$('btn-logout').onclick = signOut;
$('p-unlock').onclick = async () => {
  if (!confirm(`Take the board from ${me.owner}? Their game stops updating here.`)) return;
  await lockCall('force'); applyLock();
};

// ================= settings page =================
// Users, lights and the game lock, stored on the Pi (cgi-bin/settings). Admins only; while sign-in is
// off anyone on the home network may open it, so the first user can be created here.
function smsg(text, err) { $('settings-msg').textContent = text || ''; $('settings-msg').classList.toggle('err', !!err); }
async function settingsCall(params) {
  const opts = params
    ? { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: Object.entries(params).map(([k, v]) => k + '=' + encodeURIComponent(v)).join('&') }
    : { cache: 'no-store' };
  try {
    const res = await fetch('cgi-bin/settings', opts);
    const d = await res.json();
    if (d.ok === false) { smsg(d.error || 'Not saved.', true); return null; }
    return d;
  } catch { smsg('The Pi could not be reached.', true); return null; }
}
function renderSettings(d) {
  const list = $('users-list'); list.innerHTML = '';
  $('users-note').textContent = d.users.length
    ? 'Everyone signs in with these names. Admins can open this page and force-unlock a game.'
    : 'Sign-in is off: anyone on your network can use the scoreboard. Add a user to turn it on (the first user is admin).';
  d.users.forEach((u) => {
    const li = document.createElement('li');
    const self = u.name === d.me;
    li.innerHTML = `<span class="uname">${esc(u.name)}</span>${u.admin ? '<span class="badge">admin</span>' : ''}${self ? '<span class="hint" style="margin:0">you</span>' : ''}
      <span class="grow" style="flex:1"></span>
      <input type="password" placeholder="New password" autocomplete="new-password" hidden>
      <button data-a="pw">Change password</button>
      <button data-a="admin">${u.admin ? 'Remove admin' : 'Make admin'}</button>
      <button data-a="del" class="del">Remove</button>`;
    const inp = li.querySelector('input');
    li.querySelector('[data-a="pw"]').onclick = async (e) => {
      if (inp.hidden) { inp.hidden = false; e.target.textContent = 'Save password'; inp.focus(); return; }
      const r = await settingsCall({ action: 'user_pw', name: u.name, password: inp.value });
      if (r) { renderSettings(r); smsg(self ? 'Password changed. Your browser will ask you to sign in again.' : `Password changed for ${u.name}.`); }
    };
    li.querySelector('[data-a="admin"]').onclick = async () => {
      const r = await settingsCall({ action: 'user_admin', name: u.name, on: u.admin ? 0 : 1 });
      if (r) { renderSettings(r); smsg(`${u.name} ${u.admin ? 'is no longer admin' : 'is now admin'}.`); }
    };
    li.querySelector('[data-a="del"]').onclick = async () => {
      if (!confirm(`Remove ${u.name}?`)) return;
      const r = await settingsCall({ action: 'user_del', name: u.name });
      if (r) { renderSettings(r); smsg(`${u.name} removed.`); }
    };
    list.appendChild(li);
  });
  const L = d.lights, f = $('lights-form');
  $('lights-form').hidden = $('lights-mode').hidden = !L.installed;
  $('lights-note').textContent = L.installed
    ? 'A Tuya / Smart Life Wi-Fi plug. Changes apply within a few seconds.'
    : 'Not installed. Install it with INSTALL_LIGHTS=yes (see README).';
  if (L.installed) {
    f.device_id.value = L.device_id; f.ip.value = L.ip; f.version.value = L.version;
    f.idle_minutes.value = L.idle_minutes; f.no_score_minutes.value = L.no_score_minutes;
    f.local_key.value = ''; f.local_key.placeholder = L.key_set ? 'Saved (leave empty to keep)' : '16 characters';
    f.local_key.required = !L.key_set;
    chips($('lights-mode'), [['Automatic', 'auto'], ['Always on', 'on'], ['Always off', 'off']], L.mode, async (m) => {
      const r = await settingsCall({ action: 'lights_mode', mode: m });
      if (r) { renderSettings(r); smsg('Lights: ' + { auto: 'automatic', on: 'always on', off: 'always off' }[m] + '.'); }
    });
  }
  $('lock-form').hours.value = d.lock_hours;
}
async function openSettings() {
  smsg('');
  $('setup').classList.remove('on'); $('settings').classList.add('on');
  const d = await settingsCall();
  if (d) renderSettings(d);
}
$('btn-settings').onclick = openSettings;
$('settings-close').onclick = () => { $('settings').classList.remove('on'); lockWatch(); toSetup(true); };
$('user-add').onsubmit = async (e) => {
  e.preventDefault();
  const f = e.target, first = !$('users-list').children.length;
  const name = f.uname.value.trim();
  const r = await settingsCall({ action: 'user_add', name, password: f.password.value, admin: f.admin.checked ? 1 : 0 });
  if (!r) return;
  renderSettings(r); smsg(first ? `${name} added as admin. Sign-in is now on: your browser will ask for it.` : `${name} added.`);
  f.reset();
};
$('lights-form').onsubmit = async (e) => {
  e.preventDefault();
  const f = e.target;
  const r = await settingsCall({ action: 'lights_save', device_id: f.device_id.value, ip: f.ip.value, local_key: f.local_key.value,
    version: f.version.value, idle_minutes: f.idle_minutes.value, no_score_minutes: f.no_score_minutes.value });
  if (r) { renderSettings(r); smsg('Lights saved.'); }
};
$('lock-form').onsubmit = async (e) => {
  e.preventDefault();
  const r = await settingsCall({ action: 'lock_hours', hours: e.target.hours.value });
  if (r) { renderSettings(r); smsg('Game lock saved.'); }
};

// ================= keep the screen on =================
// While a game is open the phone or tablet shouldn't go to sleep. HTTPS pages use the Wake Lock API.
// Plain-http pages (the home address) can't, so a tiny muted looping video plays out of sight instead,
// which keeps most phones awake. Per device: menu "Keep screen on".
const AWAKE_VIDEO = 'data:video/mp4;base64,AAAAIGZ0eXBpc29tAAACAGlzb21pc28yYXZjMW1wNDEAAAW/bW9vdgAAAGxtdmhkAAAAAAAAAAAAAAAAAAAfQAAAPoAAAQAAAQAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAwAAAll0cmFrAAAAXHRraGQAAAADAAAAAAAAAAAAAAABAAAAAAAAPoAAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAAABAAAAAQAAAAAAAkZWR0cwAAABxlbHN0AAAAAAAAAAEAAD6AAAAAAAABAAAAAAHRbWRpYQAAACBtZGhkAAAAAAAAAAAAAAAAAABAAAAAgABVxAAAAAAALWhkbHIAAAAAAAAAAHZpZGUAAAAAAAAAAAAAAABWaWRlb0hhbmRsZXIAAAABfG1pbmYAAAAUdm1oZAAAAAEAAAAAAAAAAAAAACRkaW5mAAAAHGRyZWYAAAAAAAAAAQAAAAx1cmwgAAAAAQAAATxzdGJsAAAAuHN0c2QAAAAAAAAAAQAAAKhhdmMxAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAABAAEABIAAAASAAAAAAAAAABFExhdmM2My4xLjEwMiBsaWJ4MjY0AAAAAAAAAAAAAAAAGP//AAAALmF2Y0MBQsAe/+EAFmdCwB7ZHsBEAAADAAQAAAMACDxYuSABAAVoy4PEyAAAABBwYXNwAAAAAQAAAAEAAAAUYnRydAAAAAAAAApQAAAAAAAAABhzdHRzAAAAAAAAAAEAAAACAABAAAAAABRzdHNzAAAAAAAAAAEAAAABAAAAHHN0c2MAAAAAAAAAAQAAAAEAAAABAAAAAQAAABxzdHN6AAAAAAAAAAAAAAACAAACiQAAAAsAAAAYc3RjbwAAAAAAAAACAAAGAgAACKsAAAKRdHJhawAAAFx0a2hkAAAAAwAAAAAAAAAAAAAAAgAAAAAAAD6AAAAAAAAAAAAAAAABAQAAAAABAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAJGVkdHMAAAAcZWxzdAAAAAAAAAABAAA+gAAABAAAAQAAAAACCW1kaWEAAAAgbWRoZAAAAAAAAAAAAAAAAAAAH0AAAEKAVcQAAAAAAC1oZGxyAAAAAAAAAABzb3VuAAAAAAAAAAAAAAAAU291bmRIYW5kbGVyAAAAAbRtaW5mAAAAEHNtaGQAAAAAAAAAAAAAACRkaW5mAAAAHGRyZWYAAAAAAAAAAQAAAAx1cmwgAAAAAQAAAXhzdGJsAAAAfnN0c2QAAAAAAAAAAQAAAG5tcDRhAAAAAAAAAAEAAAAAAAAAAAABABAAAAAAH0AAAAAAADZlc2RzAAAAAAOAgIAlAAIABICAgBdAFQAAAAAAH0AAAAE4BYCAgAUViFblAAaAgIABAgAAABRidHJ0AAAAAAAAH0AAAAE4AAAAIHN0dHMAAAAAAAAAAgAAABAAAAQAAAAAAQAAAoAAAAAoc3RzYwAAAAAAAAACAAAAAQAAAAEAAAABAAAAAgAAAAgAAAABAAAAWHN0c3oAAAAAAAAAAAAAABEAAAATAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAABxzdGNvAAAAAAAAAAMAAAXvAAAIiwAACLYAAAAac2dwZAEAAAByb2xsAAAAAgAAAAH//wAAABxzYmdwAAAAAHJvbGwAAAABAAAAEQAAAAEAAABhdWR0YQAAAFltZXRhAAAAAAAAACFoZGxyAAAAAAAAAABtZGlyYXBwbAAAAAAAAAAAAAAAACxpbHN0AAAAJKl0b28AAAAcZGF0YQAAAAEAAAAATGF2ZjYzLjEuMTAyAAAACGZyZWUAAALvbWRhdNwATGF2YzYzLjEuMTAyAAIwQA4AAAJyBgX//27cRem95tlIt5Ys2CDZI+7veDI2NCAtIGNvcmUgMTY1IHIzMjIyIGIzNTYwNWEgLSBILjI2NC9NUEVHLTQgQVZDIGNvZGVjIC0gQ29weWxlZnQgMjAwMy0yMDI1IC0gaHR0cDovL3d3dy52aWRlb2xhbi5vcmcveDI2NC5odG1sIC0gb3B0aW9uczogY2FiYWM9MCByZWY9MyBkZWJsb2NrPTE6LTM6LTMgYW5hbHlzZT0weDE6MHgxMTEgbWU9aGV4IHN1Ym1lPTcgcHN5PTEgcHN5X3JkPTIuMDA6MC43MCBtaXhlZF9yZWY9MSBtZV9yYW5nZT0xNiBjaHJvbWFfbWU9MSB0cmVsbGlzPTEgOHg4ZGN0PTAgY3FtPTAgZGVhZHpvbmU9MjEsMTEgZmFzdF9wc2tpcD0xIGNocm9tYV9xcF9vZmZzZXQ9LTQgdGhyZWFkcz0xIGxvb2thaGVhZF90aHJlYWRzPTEgc2xpY2VkX3RocmVhZHM9MCBucj0wIGRlY2ltYXRlPTEgaW50ZXJsYWNlZD0wIGJsdXJheV9jb21wYXQ9MCBjb25zdHJhaW5lZF9pbnRyYT0wIGJmcmFtZXM9MCB3ZWlnaHRwPTAga2V5aW50PTI1MCBrZXlpbnRfbWluPTEgc2NlbmVjdXQ9NDAgaW50cmFfcmVmcmVzaD0wIHJjX2xvb2thaGVhZD00MCByYz1jcmYgbWJ0cmVlPTEgY3JmPTIzLjAgcWNvbXA9MC42MCBxcG1pbj0wIHFwbWF4PTY5IHFwc3RlcD00IGlwX3JhdGlvPTEuNDAgYXE9MToxLjIwAIAAAAAPZYiEBfOf//8PRQABV5+AARggBwEYIAcBGCAHARggBwEYIAcBGCAHARggBwEYIAcAAAAHQZo4C+c6gAEYIAcBGCAHARggBwEYIAcBGCAHARggBwEYIAcBGCAH';
let wakeSentinel = null, wakeVideo = null, screenWanted = false;
const awakeOn = () => store.get('awake', true);
async function screenOn(on) {
  screenWanted = on && awakeOn();
  if (!screenWanted) {
    try { if (wakeSentinel) await wakeSentinel.release(); } catch {}
    wakeSentinel = null;
    if (wakeVideo) wakeVideo.pause();
    return;
  }
  if ('wakeLock' in navigator && window.isSecureContext) {
    try {
      if (!wakeSentinel) {
        wakeSentinel = await navigator.wakeLock.request('screen');
        wakeSentinel.addEventListener('release', () => { wakeSentinel = null; });
      }
      return;
    } catch {}
  }
  if (!wakeVideo) {
    wakeVideo = document.createElement('video');
    Object.assign(wakeVideo, { muted: true, loop: true, playsInline: true, src: AWAKE_VIDEO });
    wakeVideo.setAttribute('playsinline', ''); wakeVideo.setAttribute('muted', ''); wakeVideo.setAttribute('aria-hidden', 'true');
    wakeVideo.style.cssText = 'position:fixed;left:0;bottom:0;width:1px;height:1px;opacity:0.01;pointer-events:none';
    document.body.appendChild(wakeVideo);
  }
  try { await wakeVideo.play(); } catch {}   // needs a tap on some phones; retried on the next one
}
// The browser drops the lock when the page is hidden, and some phones only play after a tap.
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible' && screenWanted) screenOn(true); });
document.addEventListener('pointerdown', () => {
  if (screenWanted && !wakeSentinel && (!wakeVideo || wakeVideo.paused)) screenOn(true);
}, true);

// ================= updates =================
// The installer stamps BUILD into the page and writes the same value to the file "build". An open page
// checks it every minute and reloads when a new version is installed, but never in the middle of a game.
const BUILD = '__SCOREBOARD_BUILD__';
let updateReady = false;
const canReload = () => window.PUBLIC_VIEW || !($('game').classList.contains('on') || $('settings').classList.contains('on')
  || $('pad').classList.contains('on') || (passiveMode === 'local'));
async function checkUpdate() {
  try {
    const b = (await (await fetch('build', { cache: 'no-store' })).text()).trim();
    if (/^[0-9a-f]{12}$/.test(b) && b !== BUILD) updateReady = true;
  } catch {}
  if (updateReady && canReload()) location.reload();
}
setInterval(checkUpdate, 60000);
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') checkUpdate(); });

// ================= setup screen =================
// Players list: shared on the Pi (cgi-bin/players), cached in this browser.
let roster = store.get('roster', []);          // [{ name, games }]
roster = roster.map((r) => typeof r === 'string' ? { name: r, games: 0 } : r);
let lastLineup = store.get('lastLineup', []);
let picked = [];
let shared = false;
async function loadPlayers() {
  try {
    const res = await fetch('cgi-bin/players', { cache: 'no-store' });
    if (!res.ok) throw new Error(res.status);
    const data = await res.json();
    if (Array.isArray(data.players)) roster = data.players.map((r) => typeof r === 'string' ? { name: r, games: 0 } : r);
    if (Array.isArray(data.last)) lastLineup = data.last;
    shared = true;
  } catch { shared = false; }
  store.set('roster', roster); store.set('lastLineup', lastLineup);
  picked = picked.filter((n) => roster.some((r) => r.name === n));
  renderSetup();
}
async function savePlayers() {
  store.set('roster', roster); store.set('lastLineup', lastLineup);
  if (!shared) return;
  try {
    await fetch('cgi-bin/players', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ players: roster, last: lastLineup }) });
  } catch {}
}
function renderManage() {
  const ul = $('manage-list'); ul.innerHTML = '';
  roster.forEach((r, i) => {
    const li = document.createElement('li');
    li.innerHTML = `<input maxlength="16" aria-label="Name"><span class="count"></span>
      <button aria-label="Move up">↑</button><button aria-label="Move down">↓</button><button class="del">Remove</button>`;
    const [inp] = li.getElementsByTagName('input');
    const [up, down, del] = li.getElementsByTagName('button');
    inp.value = r.name;
    li.querySelector('.count').textContent = r.games ? `${r.games} game${r.games > 1 ? 's' : ''}` : '';
    inp.onchange = () => {
      const v = inp.value.trim();
      if (!v || roster.some((x, k) => k !== i && x.name === v)) { inp.value = r.name; return; }
      picked = picked.map((n) => n === r.name ? v : n);
      lastLineup = lastLineup.map((n) => n === r.name ? v : n);
      r.name = v; savePlayers(); renderSetup();
    };
    up.disabled = i === 0; down.disabled = i === roster.length - 1;
    up.onclick = () => { [roster[i - 1], roster[i]] = [roster[i], roster[i - 1]]; savePlayers(); renderSetup(); };
    down.onclick = () => { [roster[i + 1], roster[i]] = [roster[i], roster[i + 1]]; savePlayers(); renderSetup(); };
    del.onclick = () => {
      if (!confirm(`Remove ${r.name} from the list?`)) return;
      roster.splice(i, 1);
      picked = picked.filter((n) => n !== r.name);
      lastLineup = lastLineup.filter((n) => n !== r.name);
      savePlayers(); renderSetup();
    };
    ul.appendChild(li);
  });
  $('sync-note').textContent = shared
    ? 'The list is saved on the board computer and shared by every device.'
    : 'The board computer could not be reached, so the list is saved in this browser only.';
}
let cfg = Object.assign({ game: 'x01', legsToWin: 3, opts: {} }, store.get('cfg', {}));
if (!GAMES[cfg.game]) cfg.game = 'x01';

function gameOpts(id) {
  const saved = store.get('opts.' + id, {});
  const o = {};
  for (const op of GAMES[id].options) o[op.key] = op.key in saved ? saved[op.key] : op.def;
  return o;
}
function chips(el, options, current, onPick) {
  el.innerHTML = '';
  options.forEach(([label, v]) => {
    const b = document.createElement('button'); b.className = 'chip'; b.textContent = label;
    b.setAttribute('aria-pressed', String(v === current));
    b.onclick = () => { onPick(v); renderSetup(); };
    el.appendChild(b);
  });
}
function renderSetup() {
  const el = $('roster'); el.innerHTML = '';
  roster.forEach(({ name }) => {
    const b = document.createElement('button'); b.className = 'chip';
    const pos = picked.indexOf(name);
    b.setAttribute('aria-pressed', String(pos >= 0));
    b.textContent = name;
    if (pos >= 0) { const o = document.createElement('span'); o.className = 'order'; o.textContent = pos + 1; b.appendChild(o); }
    b.onclick = () => { pos >= 0 ? picked.splice(pos, 1) : picked.push(name); renderSetup(); };
    el.appendChild(b);
  });
  $('roster-hint').textContent = roster.length ? 'Tap names in throwing order.' : 'No players yet. Open Manage list to add them.';
  const lastOk = lastLineup.length && lastLineup.every((n) => roster.some((r) => r.name === n));
  $('btn-last').hidden = !lastOk;
  $('btn-last').textContent = lastOk ? `Same players as last game: ${lastLineup.join(', ')}` : '';
  $('btn-clear').hidden = !picked.length;
  if (!$('manage').hidden) renderManage();

  chips($('opt-game'), GAME_ORDER.map((id) => [GAMES[id].name, id]), cfg.game, (v) => { cfg.game = v; store.set('cfg', cfg); });
  const g = GAMES[cfg.game];
  $('game-rule').textContent = g.rule;
  $('rules-list').innerHTML = (RULES[cfg.game] || []).map((r) => `<li>${r}</li>`).join('');
  const opts = gameOpts(cfg.game);
  const box = $('game-opts'); box.innerHTML = '';
  for (const op of g.options) {
    const grp = document.createElement('div'); grp.className = 'opt-group';
    grp.innerHTML = `<h3>${esc(op.label)}</h3><div class="row"></div>`;
    chips(grp.querySelector('.row'), op.choices, opts[op.key], (v) => { opts[op.key] = v; store.set('opts.' + cfg.game, opts); });
    box.appendChild(grp);
  }
  chips($('opt-legs'), [['1 leg', 1], ['2 legs', 2], ['3 legs', 3], ['5 legs', 5]], cfg.legsToWin, (v) => { cfg.legsToWin = v; store.set('cfg', cfg); });

  const need = g.minPlayers || 1;
  $('start').disabled = picked.length < need;
  $('start').textContent = picked.length < need
    ? (need > 1 ? `${g.name} needs ${need} players` : 'Start game')
    : `Start ${g.name} with ${picked.length} player${picked.length > 1 ? 's' : ''}`;
  const saved = store.get('game', null);
  $('resume').hidden = !(saved && saved.v === 2 && !saved.over && GAMES[saved.cfg.game]);
  $('api').value = apiBase();
  $('opt-voice').setAttribute('aria-pressed', String(store.get('voice', true)));
  $('opt-voice').textContent = store.get('voice', true) ? 'Score caller on' : 'Score caller off';
  $('opt-tips').setAttribute('aria-pressed', String(tipsOn()));
  $('opt-tips').textContent = tipsOn() ? 'Throw tips on' : 'Throw tips off';
  $('opt-awake').setAttribute('aria-pressed', String(awakeOn()));
  $('opt-awake').textContent = awakeOn() ? 'Keep screen on' : 'Screen may sleep';
}
$('add-form').onsubmit = (e) => {
  e.preventDefault();
  const name = $('add-name').value.trim();
  if (name && !roster.some((r) => r.name === name)) { roster.push({ name, games: 0 }); picked.push(name); savePlayers(); }
  $('add-name').value = ''; renderSetup();
};
$('rules').open = !!store.get('rulesOpen', false);
$('rules').ontoggle = () => store.set('rulesOpen', $('rules').open);
$('btn-last').onclick = () => { picked = lastLineup.slice(); renderSetup(); };
$('btn-clear').onclick = () => { picked = []; renderSetup(); };
$('btn-manage').onclick = () => {
  const open = $('manage').hidden;
  $('manage').hidden = !open;
  $('btn-manage').setAttribute('aria-expanded', String(open));
  $('btn-manage').textContent = open ? 'Done' : 'Manage list';
  renderSetup();
  if (open && !roster.length) $('add-name').focus();
};
$('api-save').onclick = () => { store.set('api', $('api').value.trim().replace(/\/$/, '')); poll(); };
$('opt-voice').onclick = () => { store.set('voice', !store.get('voice', true)); renderSetup(); };
$('opt-tips').onclick = () => { store.set('tips', !tipsOn()); renderSetup(); };
$('opt-awake').onclick = () => { store.set('awake', !awakeOn()); renderSetup(); };
$('start').onclick = async () => {
  screenOn(true);
  if (!(await takeBoard())) { screenOn(false); return; }
  G = newGame({ game: cfg.game, opts: gameOpts(cfg.game), legsToWin: cfg.legsToWin, players: picked.slice() });
  lastLineup = picked.slice();
  roster.forEach((r) => { if (picked.includes(r.name)) r.games = (r.games || 0) + 1; });
  savePlayers();
  ignoreUntilClear = api.darts.length > 0; saidForVisit = false;
  startBoard().then(resetBoard); pingLights();
  save(); toGame();
};
$('resume').onclick = async () => { screenOn(true); if (!(await takeBoard())) { screenOn(false); return; } pingLights(); startBoard(); G = store.get('game', null); ignoreUntilClear = api.darts.length > 0; toGame(); };
$('btn-undo').onclick = undoOwned;
// Undo after the match ended reopens the game, so the board must be taken back first.
async function undoOwned() { if (G && G.over && !(await takeBoard())) return; undo(); }
// Asks the board service to reset (clears the current throws). Best effort: older or newer
// board versions may use a different endpoint; the scoreboard works without it.
// Starts the board's detection. Autodarts stays stopped until something starts it (autodarts.io
// does this for its own games) and stops again after its standby time without throws.
let lastStartTry = 0;
async function startBoard() {
  lastStartTry = Date.now();
  try {
    if (viaPi()) await fetch('cgi-bin/board', { method: 'POST', body: 'start' });
    else await fetch(apiBase() + '/api/start', { method: 'PUT' });
  } catch {}
}
async function resetBoard() {
  try { await fetch(viaPi() ? 'cgi-bin/board' : apiBase() + '/api/reset', { method: 'POST' }); } catch {}
}
$('btn-reset').onclick = resetBoard;
$('btn-next').onclick = () => commitVisit();
$('btn-menu').onclick = () => { if (G.over || confirm('End this game? You can resume it from the setup screen.')) toSetup(); };
$('conn-text').ondblclick = () => $('raw').classList.toggle('on');

function save() { if (G) store.set('game', G); }
// Tells the Pi a game has started, so the lights come on even before the first dart.
function pingLights() { try { fetch('cgi-bin/lights', { method: 'POST', keepalive: true }).catch(() => {}); } catch {} }
function toGame() { $('setup').classList.remove('on'); $('game').classList.add('on'); render(); screenOn(true); }
function toSetup(viewerOnly) {
  if (updateReady) setTimeout(() => location.reload(), 300);   // a newer version was installed meanwhile
  screenOn(false);
  $('game').classList.remove('on'); $('passive').classList.remove('on'); $('setup').classList.add('on'); renderSetup();
  if (viewerOnly) return;   // a display leaving passive mode must not clear the game it was showing
  if (lockedByOther()) return;
  try {
    fetch('cgi-bin/game', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{"none":true}' })
      .catch(() => {}).finally(releaseBoard);
  } catch { releaseBoard(); }
  lastPublished = '';
}

renderSetup();
// PUBLIC_VIEW is set only in the read-only public copy (public-view-install.sh): passive display, no controls.
if (window.PUBLIC_VIEW) showPassive('remote');
else {
  loadPlayers();
  if (location.hash === '#passive') showPassive('remote');
  lockWatch();
  setInterval(lockWatch, 3000);
  poll();
  setInterval(poll, 300);
}
setInterval(renderConn, 1000);
</script>
</body>
</html>
EOF_OCHE
# Served by cgi-bin/index.cgi with "Cache-Control: no-cache", so browsers always get the current
# version (a plain file is cached for hours). The build stamp lets open pages notice an update.
BUILD=$(md5sum "$DIR/app.html" | cut -c1-12)
sed -i "s/__SCOREBOARD_BUILD__/$BUILD/" "$DIR/app.html"
echo "$BUILD" > "$DIR/build"
rm -f "$DIR/index.html"
mkdir -p "$DIR/cgi-bin"
cat > "$DIR/cgi-bin/index.cgi" <<'EOF_INDEX'
#!/bin/sh
printf 'Content-Type: text/html; charset=utf-8\r\nCache-Control: no-cache\r\n\r\n'
cat ../app.html
EOF_INDEX
chmod 755 "$DIR" "$DIR/cgi-bin" "$DIR/cgi-bin/index.cgi"; chmod 644 "$DIR/app.html" "$DIR/build"

echo "== Shared player list"
mkdir -p "$DIR/cgi-bin" "$DIR/data"
cat > "$DIR/cgi-bin/players" <<'EOF_CGI'
#!/bin/sh
# Shared player list for Darts Scoreboard. GET returns it, POST replaces it.
F=/data/scoreboard/data/players.json
printf 'Content-Type: application/json\r\nCache-Control: no-store\r\n\r\n'
if [ "$REQUEST_METHOD" = POST ]; then
  len=${CONTENT_LENGTH:-0}
  case "$len" in ''|*[!0-9]*) len=0 ;; esac
  if [ "$len" -gt 0 ] && [ "$len" -le 65536 ]; then
    body=$(head -c "$len")
    case "$body" in
      '{'*'}') printf '%s' "$body" > "$F.tmp" && mv "$F.tmp" "$F" && echo '{"ok":true}' && exit 0 ;;
    esac
  fi
  echo '{"ok":false}'
  exit 0
fi
if [ -f "$F" ]; then cat "$F"; else echo '{"players":[],"last":[]}'; fi
EOF_CGI
cat > "$DIR/cgi-bin/lights" <<'EOF_LIGHTS'
#!/bin/sh
# The scoreboard calls this when a game starts. The lights service (if installed) treats it as activity.
printf 'Content-Type: application/json\r\nCache-Control: no-store\r\n\r\n'
touch /data/lights/ping 2>/dev/null && echo '{"ok":true}' || echo '{"ok":false}'
EOF_LIGHTS
cat > "$DIR/cgi-bin/game" <<'EOF_GAME'
#!/bin/sh
# Live view of the running game for the passive display. The scoring device POSTs it, displays GET it.
# Kept in RAM (/tmp): it is only needed while a game is on. Only the user holding the game lock may post.
F=/tmp/scoreboard-game.json
printf 'Content-Type: application/json\r\nCache-Control: no-store\r\n\r\n'
if [ "$REQUEST_METHOD" = POST ]; then
  . /data/scoreboard-auth/lock.sh
  lock_mutex
  may_write || { echo '{"ok":false,"locked":true}'; exit 0; }
  touch "$SEEN"
  len=${CONTENT_LENGTH:-0}
  case "$len" in ''|*[!0-9]*) len=0 ;; esac
  if [ "$len" -gt 0 ] && [ "$len" -le 131072 ]; then
    body=$(head -c "$len")
    case "$body" in
      '{'*'}') printf '%s' "$body" > "$F.tmp" && mv "$F.tmp" "$F" && echo '{"ok":true}' && exit 0 ;;
    esac
  fi
  echo '{"ok":false}'
  exit 0
fi
if [ -f "$F" ]; then cat "$F"; else echo '{"none":true}'; fi
EOF_GAME
cat > "$DIR/cgi-bin/board" <<'EOF_BOARD'
#!/bin/sh
# Board access for pages opened over HTTPS (the internet link): state (GET); POST "start" starts
# the board, any other POST resets it. Start and reset are allowed only for the game lock holder.
printf 'Content-Type: application/json\r\nCache-Control: no-store\r\n\r\n'
if [ "$REQUEST_METHOD" = POST ]; then
  . /data/scoreboard-auth/lock.sh
  len=${CONTENT_LENGTH:-0}
  case "$len" in ''|*[!0-9]*) len=0 ;; esac
  [ "$len" -le 16 ] || len=16
  act=$(head -c "$len")
  lock_mutex
  may_write || { echo '{"ok":false,"locked":true}'; exit 0; }
  if [ "$act" = start ]; then
    # The board API starts on PUT, which busybox wget can't send.
    printf 'PUT /api/start HTTP/1.0\r\nHost: 127.0.0.1\r\nContent-Length: 0\r\n\r\n' | nc -w 5 127.0.0.1 3180 >/dev/null 2>&1
  else
    wget -qO /dev/null -T 3 --post-data= http://127.0.0.1:3180/api/reset 2>/dev/null
  fi
  echo '{"ok":true}'
  exit 0
fi
wget -qO- -T 3 http://127.0.0.1:3180/api/state 2>/dev/null || echo '{}'
EOF_BOARD
cat > "$DIR/cgi-bin/settings" <<'EOF_SET'
#!/bin/sh
# Settings page back end: users, lights and the game lock. GET returns them, POST changes one thing.
# Admins only. While no users exist it works only from the home network, never through the internet link.
. /data/scoreboard-auth/lock.sh
AUTH=/data/scoreboard-auth; CONF=$AUTH/httpd.conf; ADM=$AUTH/admins
SET=/data/scoreboard/data/settings
LPY=/data/lights/venv/bin/python; LCONF=/data/lights/config.json; LMODE=/data/lights/mode
printf 'Content-Type: application/json\r\nCache-Control: no-store\r\n\r\n'
fail() { printf '{"ok":false,"error":"%s"}\n' "$1"; exit 0; }
users() { sed -n 's#^/:\([^:]*\):.*#\1#p' "$CONF"; }
nusers=$(users | grep -c .)
if [ "$nusers" -gt 0 ]; then
  is_admin || fail "Only admins can change settings."
else
  case "$REMOTE_ADDR" in 127.*|::1|::ffff:127.*) fail "Add the first user from the home network." ;; esac
fi
reload() { pkill -HUP -f "httpd -f -p [0-9]* -h /data/scoreboard -c" 2>/dev/null; }
set_file() { cat > /tmp/sb-set.$$ && cat /tmp/sb-set.$$ > "$1"; rm -f /tmp/sb-set.$$; }

if [ "$REQUEST_METHOD" = POST ]; then
  len=${CONTENT_LENGTH:-0}
  case "$len" in ''|*[!0-9]*) len=0 ;; esac
  [ "$len" -le 4096 ] || fail "Too much data."
  body=$(head -c "$len")
  get() { v=$(printf '%s' "$body" | tr '&' '\n' | sed -n "s/^$1=//p" | head -1); [ -n "$v" ] && httpd -d "$v"; }
  lock_mutex
  name=$(get name)
  case "$(get action)" in
    user_add|user_pw)
      act=$(get action); pw=$(get password)
      echo "$name" | grep -qE '^[A-Za-z0-9_.-]{1,24}$' || fail "Name: 1-24 letters, digits, _ . or -"
      [ ${#pw} -ge 6 ] || fail "Password: at least 6 characters."
      case "$pw" in *:*) fail "A password can't contain a colon." ;; esac
      if users | grep -qx "$name"; then [ "$act" = user_add ] && fail "$name already exists."
      else [ "$act" = user_pw ] && fail "No user $name."; fi
      h=$(httpd -m "$pw")
      { grep -v "^/:$name:" "$CONF"; echo "/:$name:$h"; } | set_file "$CONF"
      if [ "$act" = user_add ] && { [ "$nusers" -eq 0 ] || [ "$(get admin)" = 1 ]; }; then
        grep -qx "$name" "$ADM" || echo "$name" >> "$ADM"
      fi
      reload ;;
    user_del)
      users | grep -qx "$name" || fail "No user $name."
      [ "$name" = "$ME" ] && fail "You can't remove yourself."
      grep -qx "$name" "$ADM" && [ "$(grep -c . "$ADM")" -le 1 ] && fail "Keep at least one admin."
      grep -v "^/:$name:" "$CONF" | set_file "$CONF"
      grep -vx "$name" "$ADM" | set_file "$ADM"
      reload ;;
    user_admin)
      users | grep -qx "$name" || fail "No user $name."
      if [ "$(get on)" = 1 ]; then grep -qx "$name" "$ADM" || echo "$name" >> "$ADM"
      else
        [ "$name" = "$ME" ] && fail "You can't remove your own admin rights."
        grep -qx "$name" "$ADM" && [ "$(grep -c . "$ADM")" -le 1 ] && fail "Keep at least one admin."
        grep -vx "$name" "$ADM" | set_file "$ADM"
      fi ;;
    lights_mode)
      [ -w "$LMODE" ] || fail "Lights are not installed."
      case "$(get mode)" in auto|on|off) get mode > "$LMODE" ;; *) fail "Unknown mode." ;; esac ;;
    lights_save)
      [ -x "$LPY" ] || fail "Lights are not installed."
      err=$(L_ID=$(get device_id) L_IP=$(get ip) L_KEY=$(get local_key) L_VER=$(get version) \
            L_IDLE=$(get idle_minutes) L_NOSCORE=$(get no_score_minutes) "$LPY" - <<'PY'
import json, os, re, sys
p = "/data/lights/config.json"
try:
    c = json.load(open(p))
except Exception:
    c = {"api": "http://127.0.0.1:3180/api/state"}
e = os.environ
def bad(m):
    print(m); sys.exit(1)
did, ip, key, ver = e["L_ID"].strip(), e["L_IP"].strip(), e["L_KEY"], e["L_VER"].strip()
if not re.fullmatch(r"[A-Za-z0-9]{10,40}", did): bad("The device ID looks wrong.")
if not re.fullmatch(r"(\d{1,3}\.){3}\d{1,3}", ip) or any(int(x) > 255 for x in ip.split(".")): bad("The IP address looks wrong.")
if key and len(key) != 16: bad("The local key must be 16 characters.")
if not key and not c.get("local_key"): bad("Enter the local key.")
if ver not in ("3.1", "3.2", "3.3", "3.4", "3.5"): bad("Unknown protocol version.")
mins = []
for v in (e["L_IDLE"], e["L_NOSCORE"]):
    if not re.fullmatch(r"\d{1,3}", v.strip()) or not 1 <= int(v) <= 240: bad("Minutes must be 1 to 240.")
    mins.append(int(v))
c.update(device_id=did, ip=ip, version=float(ver), idle_minutes=mins[0], no_score_minutes=mins[1])
if key:
    c["local_key"] = key
open(p, "w").write(json.dumps(c, indent=2) + "\n")
PY
) || fail "$err" ;;
    lock_hours)
      h=$(get hours)
      case "$h" in ''|*[!0-9]*) fail "Hours must be 1 to 48." ;; esac
      [ "$h" -ge 1 ] && [ "$h" -le 48 ] || fail "Hours must be 1 to 48."
      echo "LOCK_HOURS=$h" | set_file "$SET" ;;
    *) fail "Unknown action." ;;
  esac
fi

# current settings
printf '{"ok":true,"me":"%s","users":[' "$ME"
sep=
for u in $(users); do
  a=false; grep -qx "$u" "$ADM" && a=true
  printf '%s{"name":"%s","admin":%s}' "$sep" "$u" "$a"; sep=,
done
lights='{"installed":false}'
if [ -x "$LPY" ]; then
  lights=$("$LPY" - <<'PY'
import json
try:
    c = json.load(open("/data/lights/config.json"))
except Exception:
    c = {}
try:
    mode = open("/data/lights/mode").read().strip() or "auto"
except OSError:
    mode = "auto"
print(json.dumps({"installed": True, "device_id": c.get("device_id", ""), "ip": c.get("ip", ""),
                  "version": str(c.get("version", 3.3)), "idle_minutes": c.get("idle_minutes", 10),
                  "no_score_minutes": c.get("no_score_minutes", 15), "key_set": bool(c.get("local_key")), "mode": mode}))
PY
) || lights='{"installed":false}'
fi
hours=$(sed -n 's/^LOCK_HOURS=\([0-9]\{1,2\}\)$/\1/p' "$SET" 2>/dev/null)
printf '],"lights":%s,"lock_hours":%s}\n' "$lights" "${hours:-3}"
EOF_SET
cat > "$DIR/cgi-bin/lock" <<'EOF_LOCK'
#!/bin/sh
# Game lock. GET: who I am and who holds the board. POST body: acquire | release | force (admins).
. /data/scoreboard-auth/lock.sh
printf 'Content-Type: application/json\r\nCache-Control: no-store\r\n\r\n'
ok=true
if [ "$REQUEST_METHOD" = POST ]; then
  len=${CONTENT_LENGTH:-0}
  case "$len" in ''|*[!0-9]*) len=0 ;; esac
  [ "$len" -le 16 ] || len=16
  act=$(head -c "$len")
  lock_mutex
  o=$(lock_owner)
  case "$act" in
    acquire)
      if [ -z "$o" ] || [ "$o" = "$ME" ]; then
        [ -n "$ME" ] && echo "$(date +%s) $ME" > "$LOCK"
        touch "$SEEN"
      else ok=false; fi ;;
    release) if [ -z "$o" ] || [ "$o" = "$ME" ]; then rm -f "$LOCK"; else ok=false; fi ;;
    force) if is_admin; then rm -f "$LOCK"; else ok=false; fi ;;
    *) ok=false ;;
  esac
fi
o=$(lock_owner)
admin=false; is_admin && admin=true
printf '{"ok":%s,"me":"%s","owner":"%s","admin":%s}\n' "$ok" "$ME" "$o" "$admin"
EOF_LOCK
chmod 755 "$DIR/cgi-bin" "$DIR/cgi-bin/players" "$DIR/cgi-bin/lights" "$DIR/cgi-bin/game" "$DIR/cgi-bin/board" "$DIR/cgi-bin/lock" "$DIR/cgi-bin/settings"
[ -f "$DIR/data/players.json" ] || echo '{"players":[],"last":[]}' > "$DIR/data/players.json"
chown -R nobody "$DIR/data"

echo "== Sign-in and game lock"
mkdir -p "$AUTH"
[ -f "$AUTH/httpd.conf" ] || : > "$AUTH/httpd.conf"
[ -f "$AUTH/admins" ] || : > "$AUTH/admins"
cat > "$AUTH/lock.sh" <<'EOF_LIB'
# Sourced by the scoreboard CGIs. The game lock is one line "EPOCH USER" in $LOCK.
# A lock is dropped when its owner has shown no activity (game posts) for LOCK_HOURS.
LOCK=/data/scoreboard/data/lock
SEEN=/tmp/scoreboard-lock-seen
LOCK_HOURS=$(sed -n 's/^LOCK_HOURS=\([0-9]\{1,2\}\)$/\1/p' /data/scoreboard/data/settings 2>/dev/null)
[ -n "$LOCK_HOURS" ] && [ "$LOCK_HOURS" -ge 1 ] || LOCK_HOURS=3
ME=${REMOTE_USER:-}
lock_mutex() { exec 9>/tmp/scoreboard-lock.mutex; flock 9; }
lock_owner() {   # prints the user holding a live lock, or nothing
  [ -s "$LOCK" ] || return 0
  read -r t u < "$LOCK"
  case "$t" in ''|*[!0-9]*) rm -f "$LOCK"; return 0 ;; esac
  last=$t
  if [ -f "$SEEN" ]; then s=$(date -r "$SEEN" +%s 2>/dev/null); [ -n "$s" ] && [ "$s" -gt "$last" ] && last=$s; fi
  if [ $(( $(date +%s) - last )) -gt $(( LOCK_HOURS * 3600 )) ]; then rm -f "$LOCK"; return 0; fi
  printf '%s' "$u"
}
may_write() { o=$(lock_owner); [ -z "$o" ] || [ "$o" = "$ME" ]; }
is_admin() { [ -n "$ME" ] && grep -qx "$ME" /data/scoreboard-auth/admins 2>/dev/null; }
EOF_LIB
chown -R root:nobody "$AUTH"; chmod 750 "$AUTH"; chmod 640 "$AUTH/lock.sh"
chown nobody "$AUTH/httpd.conf" "$AUTH/admins"; chmod 600 "$AUTH/httpd.conf" "$AUTH/admins"   # edited by the Settings page

cat > /usr/local/sbin/scoreboard-user <<'EOF_USER'
#!/bin/sh
# scoreboard-user: manage sign-in for the Darts Scoreboard scoreboard.
#   scoreboard-user add NAME      add a user (asks for a password); the first user becomes admin
#   scoreboard-user passwd NAME   change a password
#   scoreboard-user del NAME      remove a user
#   scoreboard-user admin NAME    make a user admin, or remove admin if they are one
#   scoreboard-user list          list users (* = admin)
#   scoreboard-user unlock        release the game lock
AUTH=/data/scoreboard-auth
CONF=$AUTH/httpd.conf
ADM=$AUTH/admins
[ "$(id -u)" = 0 ] || { echo "Run as root."; exit 1; }
name_ok() { echo "$1" | grep -qE '^[A-Za-z0-9_.-]{1,24}$' || { echo "Name: 1-24 letters, digits, _ . -"; exit 1; }; }
has() { grep -q "^/:$1:" "$CONF"; }
reload() { rc-service scoreboard restart >/dev/null 2>&1; }
ask_pw() {
  while :; do
    printf 'Password for %s: ' "$1"; stty -echo 2>/dev/null; read -r p1; stty echo 2>/dev/null; echo
    printf 'Again: ';                stty -echo 2>/dev/null; read -r p2; stty echo 2>/dev/null; echo
    [ "$p1" = "$p2" ] || { echo "Passwords differ."; continue; }
    [ ${#p1} -ge 6 ] || { echo "At least 6 characters."; continue; }
    case "$p1" in *:*) echo "No colons, please."; continue ;; esac
    break
  done
  PW=$p1
}
set_pw() {
  ask_pw "$1"
  h=$(httpd -m "$PW"); unset PW p1 p2
  grep -v "^/:$1:" "$CONF" > "$CONF.new"; echo "/:$1:$h" >> "$CONF.new"
  cat "$CONF.new" > "$CONF"; rm -f "$CONF.new"
}
case "$1" in
  add)    name_ok "$2"; has "$2" && { echo "$2 exists; use passwd."; exit 1; }
          first=; grep -q '^/:' "$CONF" || first=1
          set_pw "$2"; [ -n "$first" ] && { echo "$2" >> "$ADM"; echo "$2 is admin (first user)."; }
          reload; echo "Added $2." ;;
  passwd) name_ok "$2"; has "$2" || { echo "No user $2."; exit 1; }; set_pw "$2"; reload; echo "Password changed." ;;
  del)    name_ok "$2"; has "$2" || { echo "No user $2."; exit 1; }
          grep -v "^/:$2:" "$CONF" > "$CONF.new"; cat "$CONF.new" > "$CONF"; rm -f "$CONF.new"
          grep -vx "$2" "$ADM" > "$ADM.new"; cat "$ADM.new" > "$ADM"; rm -f "$ADM.new"
          reload; echo "Removed $2."
          grep -q '^/:' "$CONF" || echo "No users left: the scoreboard is open without sign-in." ;;
  admin)  name_ok "$2"; has "$2" || { echo "No user $2."; exit 1; }
          if grep -qx "$2" "$ADM"; then grep -vx "$2" "$ADM" > "$ADM.new"; cat "$ADM.new" > "$ADM"; rm -f "$ADM.new"; echo "$2 is no longer admin."
          else echo "$2" >> "$ADM"; echo "$2 is admin."; fi ;;
  list)   sed -n 's#^/:\([^:]*\):.*#\1#p' "$CONF" | while read -r u; do grep -qx "$u" "$ADM" && echo "* $u" || echo "  $u"; done ;;
  unlock) rm -f /data/scoreboard/data/lock; echo "Game lock released." ;;
  *)      sed -n '2,9s/^# \{0,1\}//p' "$0"; exit 1 ;;
esac
EOF_USER
chmod 755 /usr/local/sbin/scoreboard-user
lbu include /usr/local/sbin/scoreboard-user

echo "== Creating the boot service"
cat > /etc/init.d/scoreboard <<EOF
#!/sbin/openrc-run
name="scoreboard"
description="Darts Scoreboard scoreboard on port $PORT"
command="$HTTPD"
command_args="-f -p $PORT -h $DIR -c $AUTH/httpd.conf -r Darts-Scoreboard"
command_user="nobody"
supervisor="supervise-daemon"
respawn_delay=5
respawn_max=0

depend() {
    need net localmount
}
EOF
chmod 755 /etc/init.d/scoreboard
rc-update add scoreboard default >/dev/null
lbu include /etc/init.d/scoreboard

echo "== Saving and starting"
apk cache sync >/dev/null 2>&1 || true
lbu commit -d
rc-service scoreboard restart >/dev/null 2>&1 || rc-service scoreboard start
sleep 1
# 401 counts as up: it means sign-in is on.
if wget -S -qO /dev/null "http://127.0.0.1:$PORT/" 2>&1 | grep -qE "HTTP/1.[01] (200|401)"; then
  IP=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
  echo
  echo "Done. Open http://${IP:-<pi-address>}:$PORT on your tablet, phone or TV."
  if grep -q '^/:' "$AUTH/httpd.conf"; then
    echo "Sign-in is on for: $(sed -n 's#^/:\([^:]*\):.*#\1#p' "$AUTH/httpd.conf" | tr '\n' ' ')"
  else
    echo "Sign-in is OFF until you add a user:  scoreboard-user add NAME"
  fi
else
  echo "The scoreboard service did not answer. Check: rc-service scoreboard status"
  exit 1
fi
