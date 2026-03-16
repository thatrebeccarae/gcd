#!/bin/bash
# auto-retro-and-report.sh — wrapper that chains retro + weekly report
# Run via LaunchAgent (com.gcd.auto-retro) for keychain access.
# Also triggered by export watcher via: ssh your-server "launchctl kickstart gui/$(id -u)/com.gcd.auto-retro"

set -uo pipefail
# Note: NOT using -e here — we want the weekly report to run even if retro exits non-zero

~/auto-retro.sh
RETRO_EXIT=$?

if [ $RETRO_EXIT -ne 0 ]; then
  echo "[$(date '+%H:%M:%S')] WARNING: auto-retro exited with code $RETRO_EXIT — running weekly report anyway"
fi

~/auto-weekly-report.sh
