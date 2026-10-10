#!/bin/sh
# This code was generated with AI (Claude by Anthropic). MIT License, see LICENSE and README.
# deploy.sh: copy this folder to the Pi and run install.sh there. Run on your computer:  ./deploy.sh
# Needs SSH access as root to PI_HOST (set in config.env). config.env is deleted from the Pi afterwards.
set -e
cd "$(dirname "$0")"
[ -f config.env ] || { echo "Copy config.env.example to config.env and fill it in first."; exit 1; }
. ./config.env
[ -n "$PI_HOST" ] || { echo "Set PI_HOST in config.env."; exit 1; }
DEST=/tmp/darts-scoreboard
ssh "root@$PI_HOST" "rm -rf $DEST && mkdir -m 700 $DEST"
scp -q -r install.sh config.env scripts "root@$PI_HOST:$DEST/"
ssh -t "root@$PI_HOST" "cd $DEST && sh install.sh; rc=\$?; rm -f $DEST/config.env; exit \$rc"
