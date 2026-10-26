#!/bin/sh
# This code was generated with AI (Claude by Anthropic). MIT License, see LICENSE and README.
# login-banner-install.sh: the ASCII-art banner shown when you log in to the Pi (name and a dartboard).
#
# Run as root:   sh login-banner-install.sh
# Writes /etc/motd and saves it with lbu. Re-running is safe.
set -e
[ "$(id -u)" = 0 ] || { echo "Run as root."; exit 1; }
cat > /etc/motd <<'EOF_MOTD'

    _     _   _  _____   ___   ____      _     ____   _____  ____
   / \   | | | ||_   _| / _ \ |  _ \    / \   |  _ \ |_   _|/ ___|
  / _ \  | | | |  | |  | | | || | | |  / _ \  | |_) |  | |  \___ \
 / ___ \ | |_| |  | |  | |_| || |_| | / ___ \ |  _ <   | |   ___) |
/_/   \_\ \___/   |_|   \___/ |____/ /_/   \_\|_| \_\  |_|  |____/

      ,-"""""""-.
    ,'  ,-'''-.  `.         Darts board computer
   /  ,'  ,-.  `.  \        Alpine Linux on Raspberry Pi 5
  |  |   ( @ )=====>-
   \  `.  `-'  ,'  /        Autodarts v2 + scoreboard
    `.  `-...-'  ,'
      `-.......-'

EOF_MOTD
lbu include /etc/motd
lbu commit -d
echo "Done. Log in again to see it."
