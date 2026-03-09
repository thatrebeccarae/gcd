#!/bin/bash
# auto-weekly-report.sh — runs on your host after auto-retro completes
# Generates weekly LinkedIn performance report from metrics, content files,
# editorial lessons, and previous reports.
# Install: cp to ~/auto-weekly-report.sh on your host, chmod +x
# Triggered by: linkedin-export-watcher.sh (MBP) or manually

set -euo pipefail

# --- Environment ---
export PATH="~/.local/bin:~/.nvm/versions/node/v22.22.0/bin:$PATH"
if [ -f "$HOME/docker/.env" ]; then
  set -a
  source "$HOME/docker/.env"
  set +a
fi
unset ANTHROPIC_API_KEY
VAULT="~/your-vault"
CONTENT_DIR="$VAULT/03-Areas/professional-content/content"
STRATEGY_DIR="$VAULT/03-Areas/professional-content/strategy"
REPORTS_DIR="$STRATEGY_DIR/weekly-reports"
METRICS_FILE="$VAULT/data/linkedin-metrics.jsonl"
LESSONS_FILE="$STRATEGY_DIR/editorial-lessons.md"
VOICE_DRIFT_FILE="$STRATEGY_DIR/voice-drift.md"
EXEMPLARS_FILE="$STRATEGY_DIR/exemplars/linkedin.md"
STRATEGY_FILE="$STRATEGY_DIR/linkedin-content-strategy.md"
EXPORT_DIR="$VAULT/04-Resources/linkedin-data/export-primary"
TODAY=$(date +%Y-%m-%d)
LOG_DIR="$VAULT/01-Inbox/pipeline-runs"
LOG="$LOG_DIR/${TODAY}-weekly-report.log"

mkdir -p "$LOG_DIR" "$REPORTS_DIR"

log() {
  echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"
}

log "=== Weekly Report Generation Started ==="
log "Date: $TODAY"

# --- Step 1: Determine week number and period ---
# Find the latest existing report to determine week number
PREV_REPORT=$(ls -t "$REPORTS_DIR"/*.md 2>/dev/null | head -1 || echo "")
PREV_WEEK_NUM=0
PREV_REPORT_CONTENT=""
if [ -n "$PREV_REPORT" ] && [ -f "$PREV_REPORT" ]; then
  PREV_WEEK_NUM=$(grep -o 'report-week: [0-9]*' "$PREV_REPORT" | awk '{print $2}' || echo "0")
  PREV_REPORT_CONTENT=$(cat "$PREV_REPORT")
  log "Previous report: $(basename "$PREV_REPORT") (Week $PREV_WEEK_NUM)"
else
  log "No previous report found"
fi

WEEK_NUM=$((PREV_WEEK_NUM + 1))
# Calculate period: last 7 days
PERIOD_START=$(python3 -c "from datetime import datetime, timedelta; print((datetime.strptime('$TODAY', '%Y-%m-%d') - timedelta(days=6)).strftime('%Y-%m-%d'))")
PERIOD_END="$TODAY"
log "Generating Week $WEEK_NUM report ($PERIOD_START to $PERIOD_END)"

# --- Step 2: Gather content library inventory ---
log "--- INVENTORY: Scanning content library ---"

INVENTORY=$(python3 -c "
import json, os, glob, re

content_dir = '$CONTENT_DIR'
results = {
    'by_status': {},
    'by_platform': {},
    'total': 0,
    'new_this_week': [],
    'rejected': []
}

period_start = '$PERIOD_START'

for year_dir in glob.glob(os.path.join(content_dir, '*')):
    if not os.path.isdir(year_dir):
        continue
    for fpath in glob.glob(os.path.join(year_dir, '*.md')):
        if fpath.endswith('.draft.md'):
            continue
        try:
            with open(fpath, 'r') as f:
                text = f.read(4096)
            m = re.match(r'^---\s*\n(.*?)\n---', text, re.DOTALL)
            if not m:
                continue
            fm = {}
            for line in m.group(1).split('\n'):
                if ':' in line:
                    key, _, val = line.partition(':')
                    fm[key.strip()] = val.strip().strip('\"').strip(\"'\")

            status = fm.get('status', 'unknown')
            platform = fm.get('platform', 'unknown')
            created = fm.get('created', '')

            results['by_status'][status] = results['by_status'].get(status, 0) + 1
            results['by_platform'][platform] = results['by_platform'].get(platform, 0) + 1
            results['total'] += 1

            if created >= period_start:
                results['new_this_week'].append({
                    'file': os.path.basename(fpath),
                    'status': status,
                    'platform': platform,
                    'title': fm.get('title', ''),
                    'source': fm.get('source', 'pipeline')
                })

            if status == 'rejected':
                results['rejected'].append({
                    'file': os.path.basename(fpath),
                    'title': fm.get('title', ''),
                    'rejection_reason': fm.get('rejection_reason', '')
                })
        except Exception:
            pass

print(json.dumps(results, indent=2))
")

log "Content inventory gathered"

# --- Step 3: Gather metrics summary ---
log "--- METRICS: Processing metrics data ---"

METRICS_SUMMARY=""
if [ -f "$METRICS_FILE" ]; then
  METRICS_SUMMARY=$(python3 -c "
import json, re, os, glob

metrics_file = '$METRICS_FILE'
content_dir = '$CONTENT_DIR'
period_start = '$PERIOD_START'

# Deduplicate metrics
seen = {}
with open(metrics_file, 'r') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
            aid = entry.get('activityId') or entry.get('activity_id') or entry.get('id')
            if aid:
                seen[aid] = entry
        except json.JSONDecodeError:
            pass

metrics = list(seen.values())

# Calculate aggregate stats
total_impressions = 0
total_reactions = 0
total_comments = 0
total_shares = 0
engagement_rates = []

for m in metrics:
    imp = int(m.get('impressions', 0) or 0)
    react = int(m.get('reactions', 0) or m.get('likes', 0) or 0)
    comm = int(m.get('comments', 0) or 0)
    sh = int(m.get('shares', 0) or m.get('reposts', 0) or 0)
    total_impressions += imp
    total_reactions += react
    total_comments += comm
    total_shares += sh
    if imp > 0:
        engagement_rates.append((react + comm + sh) / imp)

avg_eng = sum(engagement_rates) / len(engagement_rates) if engagement_rates else 0
sorted_rates = sorted(engagement_rates)
median_eng = sorted_rates[len(sorted_rates)//2] if sorted_rates else 0

# Top performers
top_by_impressions = sorted(metrics, key=lambda x: int(x.get('impressions', 0) or 0), reverse=True)[:5]
top_by_engagement = sorted(metrics, key=lambda x: (int(x.get('reactions', 0) or 0) + int(x.get('comments', 0) or 0) + int(x.get('shares', 0) or 0)) / max(int(x.get('impressions', 1) or 1), 1), reverse=True)[:5]

summary = {
    'total_posts_measured': len(metrics),
    'total_impressions': total_impressions,
    'total_reactions': total_reactions,
    'total_comments': total_comments,
    'total_shares': total_shares,
    'avg_engagement_rate': round(avg_eng * 100, 2),
    'median_engagement_rate': round(median_eng * 100, 2),
    'top_by_impressions': [{
        'activity_id': m.get('activityId') or m.get('activity_id'),
        'impressions': int(m.get('impressions', 0) or 0),
        'reactions': int(m.get('reactions', 0) or m.get('likes', 0) or 0),
        'comments': int(m.get('comments', 0) or 0)
    } for m in top_by_impressions],
    'top_by_engagement': [{
        'activity_id': m.get('activityId') or m.get('activity_id'),
        'impressions': int(m.get('impressions', 0) or 0),
        'reactions': int(m.get('reactions', 0) or m.get('likes', 0) or 0),
        'comments': int(m.get('comments', 0) or 0),
        'eng_rate': round((int(m.get('reactions', 0) or 0) + int(m.get('comments', 0) or 0) + int(m.get('shares', 0) or 0)) / max(int(m.get('impressions', 1) or 1), 1) * 100, 2)
    } for m in top_by_engagement]
}

print(json.dumps(summary, indent=2))
")
  log "Metrics summary calculated"
else
  log "WARNING: No metrics file found"
fi

# --- Step 4: Read the latest auto-retro log ---
RETRO_LOG=""
RETRO_LOG_FILE="$LOG_DIR/${TODAY}-auto-retro.log"
if [ -f "$RETRO_LOG_FILE" ]; then
  RETRO_LOG=$(tail -20 "$RETRO_LOG_FILE")
  log "Auto-retro log loaded"
else
  # Try yesterday
  YESTERDAY=$(python3 -c "from datetime import datetime, timedelta; print((datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d'))")
  RETRO_LOG_FILE="$LOG_DIR/${YESTERDAY}-auto-retro.log"
  if [ -f "$RETRO_LOG_FILE" ]; then
    RETRO_LOG=$(tail -20 "$RETRO_LOG_FILE")
    log "Auto-retro log loaded (from yesterday)"
  fi
fi

# --- Step 5: Read LinkedIn export connection data ---
EXPORT_INSIGHTS=""
LATEST_EXPORT=$(find "$EXPORT_DIR" -maxdepth 1 -type d -name "20*" 2>/dev/null | sort -r | head -1)
if [ -n "$LATEST_EXPORT" ]; then
  EXPORT_INSIGHTS=$(python3 -c "
import csv, os, json
from datetime import datetime, timedelta
from collections import Counter

export_dir = '$LATEST_EXPORT'
today = '$TODAY'
period_start = '$PERIOD_START'

insights = {}

# Connection growth
conn_file = os.path.join(export_dir, 'Connections.csv')
if os.path.exists(conn_file):
    new_connections = 0
    monthly = Counter()
    with open(conn_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            date_str = row.get('Connected On', '').strip()
            if not date_str:
                continue
            try:
                # LinkedIn uses multiple date formats
                for fmt in ['%d %b %Y', '%Y-%m-%d', '%m/%d/%y']:
                    try:
                        dt = datetime.strptime(date_str, fmt)
                        break
                    except ValueError:
                        continue
                else:
                    continue
                month_key = dt.strftime('%Y-%m')
                monthly[month_key] += 1
                if dt.strftime('%Y-%m-%d') >= period_start:
                    new_connections += 1
            except Exception:
                pass
    insights['new_connections_this_week'] = new_connections
    insights['monthly_connections'] = dict(sorted(monthly.items())[-6:])

# Shares count this period
shares_file = os.path.join(export_dir, 'Shares.csv')
if os.path.exists(shares_file):
    posts_this_week = 0
    total_posts = 0
    with open(shares_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            total_posts += 1
            date_str = row.get('Date', '')[:10]
            if date_str >= period_start:
                posts_this_week += 1
    insights['posts_this_week'] = posts_this_week
    insights['total_posts_in_export'] = total_posts

print(json.dumps(insights, indent=2))
" 2>>"$LOG")
  log "Export insights gathered from: $(basename "$LATEST_EXPORT")"
fi

# --- Step 6: Read supporting files ---
LESSONS_CONTENT=""
[ -f "$LESSONS_FILE" ] && LESSONS_CONTENT=$(head -100 "$LESSONS_FILE")

VOICE_DRIFT_CONTENT=""
[ -f "$VOICE_DRIFT_FILE" ] && VOICE_DRIFT_CONTENT=$(head -50 "$VOICE_DRIFT_FILE")

STRATEGY_CONTENT=""
[ -f "$STRATEGY_FILE" ] && STRATEGY_CONTENT=$(head -100 "$STRATEGY_FILE")

# --- Step 7: Generate report via Claude ---
log "--- REPORT: Generating weekly report via Claude ---"

REPORT_FILE="$REPORTS_DIR/${TODAY}-week-$(printf '%02d' $WEEK_NUM).md"

# Truncate previous report for context (keep first 3000 chars)
PREV_REPORT_TRUNCATED=""
if [ -n "$PREV_REPORT_CONTENT" ]; then
  PREV_REPORT_TRUNCATED=$(echo "$PREV_REPORT_CONTENT" | head -c 3000)
fi

REPORT_PROMPT="You are generating a weekly LinkedIn performance report for Your Name's content strategy.

REPORT METADATA:
- Week number: $WEEK_NUM
- Period: $PERIOD_START to $PERIOD_END
- Date: $TODAY

CONTENT LIBRARY INVENTORY:
$INVENTORY

METRICS SUMMARY (all measured posts):
$METRICS_SUMMARY

LINKEDIN EXPORT INSIGHTS (connections, posting activity):
$EXPORT_INSIGHTS

AUTO-RETRO RESULTS (from today's run):
$RETRO_LOG

EDITORIAL LESSONS (current state):
$LESSONS_CONTENT

VOICE DRIFT STATUS:
$VOICE_DRIFT_CONTENT

CONTENT STRATEGY SUMMARY:
$STRATEGY_CONTENT

PREVIOUS REPORT (for comparison/continuity):
$PREV_REPORT_TRUNCATED

Generate a complete weekly report as a markdown file. Start with this EXACT frontmatter:

---
context: professional
type: performance-report
status: complete
report-week: $WEEK_NUM
period: $PERIOD_START to $PERIOD_END
data-sources:
  - export-primary/$TODAY
  - data/linkedin-metrics.jsonl
  - content/**/*.md
strategy-ref: \"[[linkedin-content-strategy/linkedin-content-strategy|LinkedIn Content Strategy]]\"
tags: [linkedin, analytics, weekly-report, learning-loop]
---

REPORT STRUCTURE (follow this order):
1. **Executive Summary** — 2-3 sentence overview of the week. Key wins, concerns, and trajectory.
2. **Content Library State** — File inventory by status and platform. New this week. Any rejected drafts and why.
3. **Performance Analysis** — Top performers by impressions and engagement rate. What worked and why. Bottom performers and diagnosis.
4. **Feedback Loop Status** — What auto-retro found (new candidates, promotions, discards, exemplar rotations, stubs created for off-pipeline posts). Voice drift analysis status.
5. **Connection & Growth Metrics** — From LinkedIn export: new connections, monthly trajectory, posting cadence.
6. **Recommendations for Next Week** — 3-5 specific, actionable items. Reference data to support each.
7. **Updated Benchmarks** — Quartile table for impressions, engagement rate, reactions, comments.

STYLE:
- Data-driven, concise, no fluff
- Reference specific posts by name when discussing performance
- Include tables for data comparisons
- Compare to previous week where possible
- Be honest about gaps and measurement limitations

Output ONLY the complete markdown file starting with ---. No commentary, no code fences."

REPORT_OUTPUT=$(claude --print -p "$REPORT_PROMPT" 2>>"$LOG")
CLAUDE_EXIT=$?

if [ $CLAUDE_EXIT -ne 0 ] || [ -z "$REPORT_OUTPUT" ]; then
  log "ERROR: Report generation failed (exit: $CLAUDE_EXIT)"
  log "=== Weekly Report Generation Failed ==="
  exit 1
fi

# Write report (strip code fences if present)
python3 -c "
import sys, re
content = sys.stdin.read()
content = re.sub(r'^\`\`\`\w*\n', '', content)
content = re.sub(r'\n\`\`\`\s*$', '', content)
content = content.lstrip('\n')
sys.stdout.write(content)
" <<< "$REPORT_OUTPUT" > "$REPORT_FILE"

log "Report written to: $REPORT_FILE ($(wc -c < "$REPORT_FILE" | tr -d ' ') bytes)"

# --- Step 8: Slack notification ---
log "--- SLACK: Sending report notification ---"

TODAY_DISPLAY=$(date '+%b %-d')
SUMMARY=":chart_with_upwards_trend: *Weekly Report — Week ${WEEK_NUM} (${TODAY_DISPLAY})*\n\n"
SUMMARY+="Report generated: \`weekly-reports/${TODAY}-week-$(printf '%02d' $WEEK_NUM).md\`\n"
SUMMARY+="Period: ${PERIOD_START} to ${PERIOD_END}\n\n"
SUMMARY+=":mag: Open in Obsidian to review\n"
SUMMARY+=":arrows_counterclockwise: Files sync to MBP within ~1 minute via Syncthing"

if [ -n "${SLACK_CONTENT_BOT_TOKEN:-}" ] && [ -n "${SLACK_REPORTS_CHANNEL_ID:-}" ]; then
  PAYLOAD=$(python3 -c "
import json
text = '''${SUMMARY}'''
payload = {
    'channel': '${SLACK_REPORTS_CHANNEL_ID}',
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

log "=== Weekly Report Generation Complete ==="
