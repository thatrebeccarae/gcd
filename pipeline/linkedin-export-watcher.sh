#!/bin/bash
# linkedin-export-watcher.sh — runs on MBP via LaunchAgent WatchPaths
# Watches ~/Downloads/ for LinkedIn data export ZIP files
# When found: extracts to vault, triggers your host retro + weekly report
# Install: cp to ~/linkedin-export-watcher.sh on MBP, chmod +x
# LaunchAgent: com.mbp.linkedin-export-watcher — WatchPaths on ~/Downloads/

set -euo pipefail

DOWNLOADS="$HOME/Downloads"
VAULT="$HOME/your-vault"
EXPORT_DIR="$VAULT/04-Resources/linkedin-data/export-primary"
LOG_DIR="$VAULT/01-Inbox/pipeline-runs"
TODAY=$(date +%Y-%m-%d)
LOG="$LOG_DIR/${TODAY}-export-watcher.log"
LOCK_FILE="/tmp/linkedin-export-watcher.lock"

mkdir -p "$LOG_DIR"

log() {
  echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"
}

# --- Prevent concurrent runs ---
# WatchPaths fires on ANY change in ~/Downloads/, so we need to debounce
if [ -f "$LOCK_FILE" ]; then
  LOCK_AGE=$(( $(date +%s) - $(stat -f %m "$LOCK_FILE") ))
  if [ "$LOCK_AGE" -lt 300 ]; then
    # Lock is less than 5 minutes old — another run is active or just finished
    exit 0
  fi
  # Stale lock — remove it
  rm -f "$LOCK_FILE"
fi

# --- Find LinkedIn export ZIP ---
ZIP_FILE=""
for f in "$DOWNLOADS"/Complete_LinkedInDataExport_*.zip "$DOWNLOADS"/Complete_LinkedInDataExport*.zip; do
  if [ -f "$f" ]; then
    ZIP_FILE="$f"
    break
  fi
done

if [ -z "$ZIP_FILE" ]; then
  # No export ZIP found — this is normal, WatchPaths fires on all Downloads changes
  exit 0
fi

# --- Create lock file ---
touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

log "=== LinkedIn Export Watcher Triggered ==="
log "Found export: $(basename "$ZIP_FILE")"

# --- Extract to vault ---
DEST_DIR="$EXPORT_DIR/$TODAY"

if [ -d "$DEST_DIR" ]; then
  log "WARNING: Export directory already exists: $DEST_DIR"
  log "Skipping extraction — may have already been processed today"
  rm -f "$LOCK_FILE"
  exit 0
fi

mkdir -p "$DEST_DIR"
log "Extracting to: $DEST_DIR"

# LinkedIn exports sometimes have a nested directory inside the ZIP
# Use a temp dir to handle this
TEMP_DIR=$(mktemp -d)
unzip -q "$ZIP_FILE" -d "$TEMP_DIR" 2>>"$LOG"

# Check if contents are nested in a subdirectory
NESTED=$(find "$TEMP_DIR" -maxdepth 1 -type d | tail -n +2)
if [ "$(echo "$NESTED" | wc -l | tr -d ' ')" -eq 1 ] && [ -d "$NESTED" ]; then
  # Single nested directory — move its contents up
  mv "$NESTED"/* "$DEST_DIR/" 2>/dev/null || true
  mv "$NESTED"/.* "$DEST_DIR/" 2>/dev/null || true
else
  # Files are at the top level
  mv "$TEMP_DIR"/* "$DEST_DIR/" 2>/dev/null || true
fi
rm -rf "$TEMP_DIR"

# Verify extraction
if [ -f "$DEST_DIR/Shares.csv" ]; then
  SHARE_COUNT=$(wc -l < "$DEST_DIR/Shares.csv" | tr -d ' ')
  log "Extraction successful — Shares.csv has $SHARE_COUNT lines"
else
  log "WARNING: Shares.csv not found in extracted export"
  log "Contents: $(ls "$DEST_DIR" | head -10)"
fi

# --- Move ZIP to trash ---
log "Moving ZIP to trash"
mv "$ZIP_FILE" "$HOME/.Trash/" 2>/dev/null || rm "$ZIP_FILE"

# --- Wait for Syncthing sync ---
log "Waiting 90 seconds for Syncthing to propagate to your host..."
sleep 90

# --- Verify your host has the file ---
your host_HAS_FILE=$(ssh your-server "test -f '$VAULT/04-Resources/linkedin-data/export-primary/$TODAY/Shares.csv' && echo 'yes' || echo 'no'" 2>/dev/null || echo "ssh_failed")

if [ "$your host_HAS_FILE" = "yes" ]; then
  log "Confirmed: export synced to your host"
elif [ "$your host_HAS_FILE" = "no" ]; then
  log "WARNING: Export not yet on your host — waiting another 60 seconds"
  sleep 60
  your host_HAS_FILE=$(ssh your-server "test -f '$VAULT/04-Resources/linkedin-data/export-primary/$TODAY/Shares.csv' && echo 'yes' || echo 'no'" 2>/dev/null || echo "ssh_failed")
  if [ "$your host_HAS_FILE" != "yes" ]; then
    log "WARNING: Export still not on your host after 2.5 min. Retro will use whatever data is available."
  fi
else
  log "WARNING: Could not SSH to your host — retro will run on its next scheduled time"
fi

# --- Trigger auto-retro + weekly report on your host ---
# MUST use launchctl kickstart (not ssh nohup) — claude --print needs macOS keychain for OAuth
log "Triggering auto-retro via LaunchAgent on your host..."
your host_UID=$(ssh your-server "id -u" 2>/dev/null)
if [ -n "$your host_UID" ]; then
  ssh your-server "launchctl kickstart gui/${your host_UID}/com.gcd.auto-retro" 2>>"$LOG"
  if [ $? -eq 0 ]; then
    log "Auto-retro + weekly report triggered on your host (LaunchAgent kickstart)"
  else
    log "WARNING: Failed to kickstart LaunchAgent on your host"
  fi
else
  log "WARNING: Could not get your host UID — retro will run on its next scheduled time"
fi

# --- Slack notification ---
# Source Slack env vars (MBP keeps these in .zshrc, but also check docker .env)
# On MBP, export SLACK_CONTENT_BOT_TOKEN and SLACK_CONTENT_CHANNEL_ID in ~/.zshrc
if [ -z "${SLACK_CONTENT_BOT_TOKEN:-}" ]; then
  # Try sourcing from your host docker .env via Syncthing copy or local .env
  for envfile in "$HOME/docker/.env" "$HOME/.slack-env"; do
    if [ -f "$envfile" ]; then
      set -a
      source "$envfile"
      set +a
      break
    fi
  done
fi

if [ -n "${SLACK_CONTENT_BOT_TOKEN:-}" ] && [ -n "${SLACK_CONTENT_CHANNEL_ID:-}" ]; then
  TODAY_DISPLAY=$(date '+%b %-d')
  SUMMARY=":inbox_tray: *LinkedIn Export Processed — ${TODAY_DISPLAY}*\n\n"
  SUMMARY+="Export extracted to \`export-primary/$TODAY/\`\n"
  SUMMARY+="Auto-retro + weekly report triggered on your host\n"
  SUMMARY+=":arrows_counterclockwise: Results will post when complete"

  PAYLOAD=$(python3 -c "
import json
text = '''${SUMMARY}'''
payload = {
    'channel': '${SLACK_CONTENT_CHANNEL_ID}',
    'blocks': [{'type': 'section', 'text': {'type': 'mrkdwn', 'text': text}}]
}
print(json.dumps(payload))
")
  curl -s -X POST "https://slack.com/api/chat.postMessage" \
    -H "Authorization: Bearer ${SLACK_CONTENT_BOT_TOKEN}" \
    -H "Content-Type: application/json; charset=utf-8" \
    -d "$PAYLOAD" >> "$LOG" 2>&1
  log "Slack notification sent"
fi

log "=== LinkedIn Export Watcher Complete ==="
