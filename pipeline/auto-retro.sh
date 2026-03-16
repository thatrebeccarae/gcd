#!/bin/bash
# auto-retro.sh — runs weekly (Saturday 6 PM) on your host host
# Phase 6: Automated content retrospective — analyzes LinkedIn metrics,
# promotes/discards editorial-lessons candidates, rotates exemplars
# Install: cp to ~/auto-retro.sh on your host, chmod +x
# LaunchAgent: com.gcd.auto-retro — runs Saturday at 18:00

set -euo pipefail

# --- Environment ---
export PATH="~/.local/bin:~/.nvm/versions/node/v22.22.0/bin:$PATH"
# Source Docker .env for SLACK_CONTENT_BOT_TOKEN, SLACK_CONTENT_CHANNEL_ID, etc.
if [ -f "$HOME/docker/.env" ]; then
  set -a
  source "$HOME/docker/.env"
  set +a
fi
# Unset API key so claude --print uses Max subscription (setup-token) not API billing
unset ANTHROPIC_API_KEY
VAULT="~/your-vault"
CONTENT_DIR="$VAULT/03-Areas/professional-content/content"
STRATEGY_DIR="$VAULT/03-Areas/professional-content/strategy"
METRICS_FILE="$VAULT/data/linkedin-metrics.jsonl"
LESSONS_FILE="$STRATEGY_DIR/editorial-lessons.md"
EXEMPLARS_FILE="$STRATEGY_DIR/exemplars/linkedin.md"
ROTATION_LOG="$STRATEGY_DIR/exemplar-rotation-log.md"
TODAY=$(date +%Y-%m-%d)
LOG_DIR="$VAULT/01-Inbox/pipeline-runs"
LOG="$LOG_DIR/${TODAY}-auto-retro.log"

mkdir -p "$LOG_DIR"

ERRORS=0
CANDIDATES_ADDED=0
PROMOTIONS=0
DISCARDS=0
EXEMPLAR_ROTATIONS=0

log() {
  echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"
}

log "=== Auto-Retro Started ==="
log "Date: $TODAY"

# --- Step 1: Validate metrics file ---
if [ ! -f "$METRICS_FILE" ]; then
  log "ERROR: Metrics file not found: $METRICS_FILE"
  log "=== Auto-Retro Aborted — no metrics data ==="
  exit 0
fi

TOTAL_LINES=$(wc -l < "$METRICS_FILE" | tr -d ' ')
if [ "$TOTAL_LINES" -eq 0 ]; then
  log "ERROR: Metrics file is empty"
  log "=== Auto-Retro Aborted — empty metrics ==="
  exit 0
fi
log "Metrics file: $TOTAL_LINES lines"

# --- Step 2: Deduplicate metrics by activityId (keep latest per ID) ---
# Each JSONL line is {"source":..., "posts":[{activityId,...},...]} — unwrap posts array
DEDUPED_METRICS=$(python3 -c "
import json, sys

metrics_file = '$METRICS_FILE'
seen = {}
errors = 0

with open(metrics_file, 'r') as f:
    for i, line in enumerate(f, 1):
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
            # Unwrap posts array (userscript format)
            posts = entry.get('posts', [])
            if posts:
                for post in posts:
                    aid = post.get('activityId') or post.get('activity_id') or post.get('id')
                    if aid:
                        seen[aid] = post  # later entries overwrite earlier
            else:
                # Fallback: maybe it's a flat post entry
                aid = entry.get('activityId') or entry.get('activity_id') or entry.get('id')
                if aid:
                    seen[aid] = entry
                else:
                    print(f'WARN: Line {i} has no posts array and no activityId', file=sys.stderr)
                    errors += 1
        except json.JSONDecodeError:
            print(f'WARN: Line {i} is not valid JSON', file=sys.stderr)
            errors += 1

print(json.dumps(list(seen.values()), indent=2))
print(f'DEDUPED:{len(seen)}', file=sys.stderr)
if errors:
    print(f'PARSE_ERRORS:{errors}', file=sys.stderr)
" 2>>"$LOG")

DEDUPED_COUNT=$(echo "$DEDUPED_METRICS" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
log "Deduped metrics: $DEDUPED_COUNT unique posts"

if [ "$DEDUPED_COUNT" -eq 0 ]; then
  log "No valid metrics entries after dedup. Exiting."
  log "=== Auto-Retro Aborted — no valid metrics ==="
  exit 0
fi

# --- Step 3: Match metrics to content files ---
MATCHED_DATA=$(python3 -c "
import json, sys, os, re, glob

metrics = json.loads(sys.stdin.read())
content_dir = '$CONTENT_DIR'
matched = []

# Build index of content files by activity_id and post_url
file_index = {}  # activity_id -> filepath
for year_dir in glob.glob(os.path.join(content_dir, '*')):
    if not os.path.isdir(year_dir):
        continue
    for fpath in glob.glob(os.path.join(year_dir, '*.md')):
        try:
            with open(fpath, 'r') as f:
                content = f.read(4096)  # frontmatter is in first few KB
            # Extract frontmatter
            fm_match = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
            if not fm_match:
                continue
            fm = fm_match.group(1)
            # Look for activity_id or post_url with activity ID
            for line in fm.split('\n'):
                line = line.strip()
                if line.startswith('activity_id:'):
                    aid = line.split(':', 1)[1].strip().strip('\"').strip(\"'\")
                    file_index[aid] = fpath
                elif line.startswith('post_url:'):
                    url = line.split(':', 1)[1].strip().strip('\"').strip(\"'\")
                    # Extract activity ID from LinkedIn URL
                    url_match = re.search(r'activity[:-](\d+)', url)
                    if url_match:
                        file_index[url_match.group(1)] = fpath
                    # Also index the full URL fragment
                    url_match2 = re.search(r'(\d{19,20})', url)
                    if url_match2:
                        file_index[url_match2.group(1)] = fpath
        except Exception as e:
            print(f'WARN: Error reading {fpath}: {e}', file=sys.stderr)

# Match metrics to files
for m in metrics:
    aid = str(m.get('activityId') or m.get('activity_id') or m.get('id', ''))
    # Try exact match and numeric-only match
    fpath = file_index.get(aid)
    if not fpath:
        # Try just the numeric portion
        num_match = re.search(r'(\d{19,20})', aid)
        if num_match:
            fpath = file_index.get(num_match.group(1))

    if fpath:
        # Read file content for context
        with open(fpath, 'r') as f:
            file_content = f.read()
        matched.append({
            'metrics': m,
            'file': fpath,
            'file_content': file_content
        })
    else:
        # Unmatched — still include metrics for analysis
        matched.append({
            'metrics': m,
            'file': None,
            'file_content': None
        })

print(json.dumps(matched, indent=2))
print(f'MATCHED:{sum(1 for x in matched if x[\"file\"])} UNMATCHED:{sum(1 for x in matched if not x[\"file\"])}', file=sys.stderr)
" <<< "$DEDUPED_METRICS" 2>>"$LOG")

MATCHED_COUNT=$(echo "$MATCHED_DATA" | python3 -c "import json,sys; data=json.load(sys.stdin); print(sum(1 for x in data if x['file']))")
UNMATCHED_COUNT=$(echo "$MATCHED_DATA" | python3 -c "import json,sys; data=json.load(sys.stdin); print(sum(1 for x in data if not x['file']))")
log "Matched: $MATCHED_COUNT posts to files, $UNMATCHED_COUNT unmatched"

# --- Step 3b: Create stubs for unmatched posts from LinkedIn data export ---
STUBS_CREATED=0
if [ "$UNMATCHED_COUNT" -gt 0 ]; then
  log "--- STUBS: Looking up $UNMATCHED_COUNT unmatched posts in LinkedIn data export ---"

  # Find the latest LinkedIn data export directory (sorted by date folder name)
  EXPORT_BASE="$VAULT/04-Resources/linkedin-data/export-primary"
  LATEST_EXPORT=""
  if [ -d "$EXPORT_BASE" ]; then
    LATEST_EXPORT=$(find "$EXPORT_BASE" -maxdepth 1 -type d -name "20*" | sort -r | head -1)
  fi

  if [ -n "$LATEST_EXPORT" ] && [ -f "$LATEST_EXPORT/Shares.csv" ]; then
    log "Using export: $LATEST_EXPORT/Shares.csv"

    STUBS_CREATED=$(python3 -c "
import json, sys, os, re, csv, urllib.parse
from datetime import datetime

matched_data = json.loads(sys.stdin.read())
shares_csv = '$LATEST_EXPORT/Shares.csv'
content_dir = '$CONTENT_DIR'
today = '$TODAY'

# Load Shares.csv and index by activity ID extracted from ShareLink
shares_by_id = {}
with open(shares_csv, 'r', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    for row in reader:
        link = urllib.parse.unquote(row.get('ShareLink', ''))
        # Extract activity/share ID from URL
        id_match = re.search(r'(?:activity|share)[:\-](\d{19,20})', link)
        if id_match:
            shares_by_id[id_match.group(1)] = {
                'date': row.get('Date', ''),
                'link': row.get('ShareLink', ''),
                'text': row.get('ShareCommentary', ''),
                'shared_url': row.get('SharedUrl', ''),
                'visibility': row.get('Visibility', '')
            }

# Process unmatched posts
stubs_created = 0
for entry in matched_data:
    if entry['file'] is not None:
        continue  # already matched

    m = entry['metrics']
    aid = str(m.get('activityId') or m.get('activity_id') or m.get('id', ''))
    # Extract numeric ID
    num_match = re.search(r'(\d{19,20})', aid)
    if not num_match:
        continue
    numeric_id = num_match.group(1)

    # Look up in Shares.csv
    share = shares_by_id.get(numeric_id)
    if not share or not share['text']:
        print(f'SKIP: {numeric_id} — not found in Shares.csv or empty text', file=sys.stderr)
        continue

    # Parse the post date
    post_date_str = share['date'][:10] if share['date'] else today
    try:
        post_date = datetime.strptime(post_date_str, '%Y-%m-%d')
    except ValueError:
        post_date_str = today
        post_date = datetime.strptime(today, '%Y-%m-%d')

    year = post_date_str[:4]

    # Determine prefix — default to LI for LinkedIn posts
    prefix = 'LI'

    # Generate slug from first ~60 chars of text
    slug_source = share['text'][:60].strip()
    slug = re.sub(r'[^a-z0-9]+', '-', slug_source.lower()).strip('-')[:50]

    # Build output path
    output_dir = os.path.join(content_dir, 'content', year)
    output_file = os.path.join(output_dir, f'{post_date_str}-{prefix}-{slug}.md')

    # Skip if file already exists
    if os.path.exists(output_file):
        print(f'SKIP: {output_file} already exists', file=sys.stderr)
        continue

    os.makedirs(output_dir, exist_ok=True)

    # Build metrics for frontmatter
    impressions = int(m.get('impressions', 0) or 0)
    reactions = int(m.get('reactions', 0) or m.get('likes', 0) or 0)
    comments = int(m.get('comments', 0) or 0)
    shares_count = int(m.get('shares', 0) or m.get('reposts', 0) or 0)

    # Decode the post URL for frontmatter
    post_url = urllib.parse.unquote(share['link'])

    # Write the stub
    frontmatter = f'''---
title: \"\"
piece_id:
pillar:
route: linkedin
status: published
source: manual
created: {post_date_str}
platform: linkedin
context: professional
type: social
activity_id: \"{numeric_id}\"
post_url: \"{post_url}\"
impressions: {impressions}
reactions: {reactions}
comments: {comments}
shares: {shares_count}
---

'''
    content = frontmatter + share['text'] + '\n'

    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(content)

    stubs_created += 1
    print(f'CREATED: {output_file}', file=sys.stderr)

print(stubs_created)
" <<< "$MATCHED_DATA" 2>>"$LOG")

    log "Stubs created for unmatched posts: $STUBS_CREATED"
  else
    log "WARNING: No LinkedIn data export found at $EXPORT_BASE — skipping stub creation"
    log "Export Shares.csv when available, then re-run or wait for next retro cycle"
  fi
fi

# --- Step 4: Calculate engagement metrics ---
METRICS_SUMMARY=$(python3 -c "
import json, sys

data = json.loads(sys.stdin.read())
results = []
all_rates = []

for entry in data:
    m = entry['metrics']
    impressions = int(m.get('impressions', 0) or 0)
    reactions = int(m.get('reactions', 0) or m.get('likes', 0) or 0)
    comments = int(m.get('comments', 0) or 0)
    shares = int(m.get('shares', 0) or m.get('reposts', 0) or 0)

    if impressions > 0:
        eng_rate = (reactions + comments + shares) / impressions
    else:
        eng_rate = 0.0

    all_rates.append(eng_rate)
    results.append({
        'activity_id': m.get('activityId') or m.get('activity_id') or m.get('id'),
        'impressions': impressions,
        'reactions': reactions,
        'comments': comments,
        'shares': shares,
        'engagement_rate': round(eng_rate, 6),
        'file': entry.get('file'),
        'file_content': entry.get('file_content')
    })

avg_rate = sum(all_rates) / len(all_rates) if all_rates else 0
median_rates = sorted(all_rates)
median_rate = median_rates[len(median_rates)//2] if median_rates else 0

summary = {
    'posts': results,
    'avg_engagement_rate': round(avg_rate, 6),
    'median_engagement_rate': round(median_rate, 6),
    'total_posts': len(results),
    'posts_above_avg': sum(1 for r in all_rates if r > avg_rate),
    'posts_below_avg': sum(1 for r in all_rates if r <= avg_rate)
}
print(json.dumps(summary, indent=2))
" <<< "$MATCHED_DATA")

AVG_RATE=$(echo "$METRICS_SUMMARY" | python3 -c "import json,sys; print(f\"{json.load(sys.stdin)['avg_engagement_rate']*100:.2f}%\")")
log "Average engagement rate: $AVG_RATE"

# --- Step 5: Read existing editorial lessons ---
LESSONS_CONTENT=""
if [ -f "$LESSONS_FILE" ]; then
  LESSONS_CONTENT=$(cat "$LESSONS_FILE")
  log "Existing editorial-lessons.md loaded ($(wc -c < "$LESSONS_FILE" | tr -d ' ') bytes)"
else
  log "WARNING: editorial-lessons.md not found — will create if needed"
fi

# --- Step 6: Read existing exemplars ---
EXEMPLARS_CONTENT=""
if [ -f "$EXEMPLARS_FILE" ]; then
  EXEMPLARS_CONTENT=$(cat "$EXEMPLARS_FILE")
  log "Existing linkedin exemplars loaded ($(wc -c < "$EXEMPLARS_FILE" | tr -d ' ') bytes)"
else
  log "WARNING: linkedin exemplars file not found"
fi

# --- Step 7: Send to Claude for analysis ---
log "--- ANALYSIS: Sending metrics to Claude for pattern analysis ---"

# Truncate file_content in metrics summary to keep prompt manageable
ANALYSIS_INPUT=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
for post in data['posts']:
    if post.get('file_content') and len(post['file_content']) > 1500:
        post['file_content'] = post['file_content'][:1500] + '\n[...truncated...]'
print(json.dumps(data, indent=2))
" <<< "$METRICS_SUMMARY")

ANALYSIS_PROMPT="You are an editorial strategist analyzing LinkedIn content performance for Your Name's autonomous content pipeline.

METRICS DATA (with engagement rates calculated):
$ANALYSIS_INPUT

EXISTING EDITORIAL LESSONS:
$LESSONS_CONTENT

CURRENT LINKEDIN EXEMPLARS:
$EXEMPLARS_CONTENT

Analyze the data and produce THREE sections in your response, using these EXACT headers:

## PATTERN ANALYSIS
Identify content patterns that correlate with high vs low performance. Reference specific posts. Compare to the historical average engagement rate. Be specific about what works and what doesn't — name hooks, structures, topics, formats.

## CANDIDATE RULES
Propose new candidate rules for editorial-lessons.md. Each must follow this exact format:
\`\`\`
### Candidate: [rule name]
- **Pattern:** [description of the pattern]
- **Evidence:** N posts, avg engagement X%
- **First seen:** $TODAY
\`\`\`
Do NOT propose rules that duplicate or closely overlap existing ALWAYS/NEVER rules or existing candidates in the editorial lessons. Only propose rules with clear, actionable signal from the data.

## EXEMPLAR ROTATION
Evaluate whether any newly measured post should replace the lowest-performing measured exemplar (marked [MEASURED]) in the exemplars file. LinkedIn exemplars max is 7 entries.
- Compare by engagement rate only for [MEASURED] entries
- NEVER suggest removing non-measured editorial picks (entries without [MEASURED] tag)
- For each suggested rotation, state: old exemplar name, new exemplar name, engagement rates, reason
- If no rotation is warranted, say 'No rotation needed' and explain why.

Be concise and data-driven. No fluff."

ANALYSIS_OUTPUT=$(claude --print -p "$ANALYSIS_PROMPT" 2>>"$LOG")
CLAUDE_EXIT=$?

if [ $CLAUDE_EXIT -ne 0 ] || [ -z "$ANALYSIS_OUTPUT" ]; then
  log "ERROR: Claude analysis failed (exit: $CLAUDE_EXIT)"
  ERRORS=$((ERRORS + 1))
  log "=== Auto-Retro Aborted — analysis failed ==="
  exit 1
fi

log "Analysis received ($(echo "$ANALYSIS_OUTPUT" | wc -c | tr -d ' ') bytes)"

# --- Step 8: Extract and append new candidates ---
log "--- CANDIDATES: Extracting new candidate rules ---"

NEW_CANDIDATES=$(python3 -c "
import sys, re

analysis = sys.stdin.read()
existing_lessons = '''$LESSONS_CONTENT'''

# Extract candidate blocks from analysis
candidate_section = ''
in_section = False
for line in analysis.split('\n'):
    if '## CANDIDATE RULES' in line.upper():
        in_section = True
        continue
    elif line.startswith('## ') and in_section:
        break
    elif in_section:
        candidate_section += line + '\n'

# Extract individual candidates
candidates = re.findall(r'### Candidate:.*?(?=### Candidate:|\Z)', candidate_section, re.DOTALL)

# Filter out duplicates (check if rule name already exists in lessons)
new_ones = []
for c in candidates:
    c = c.strip()
    if not c:
        continue
    # Extract rule name
    name_match = re.search(r'### Candidate:\s*(.+)', c)
    if name_match:
        name = name_match.group(1).strip().lower()
        # Check if similar name already exists
        if name not in existing_lessons.lower():
            new_ones.append(c)
        else:
            print(f'SKIP_DUP: {name}', file=sys.stderr)

# Output new candidates
for c in new_ones:
    # Prepend date tag
    print(f'- [{\"$TODAY\"}] {c}')
    print()

print(f'NEW_CANDIDATES:{len(new_ones)}', file=sys.stderr)
" <<< "$ANALYSIS_OUTPUT" 2>>"$LOG")

if [ -n "$NEW_CANDIDATES" ]; then
  CANDIDATES_ADDED=$(echo "$NEW_CANDIDATES" | grep -c "### Candidate:" || echo "0")
  log "New candidates to add: $CANDIDATES_ADDED"

  if [ -f "$LESSONS_FILE" ] && [ "$CANDIDATES_ADDED" -gt 0 ]; then
    # Append to candidates section
    echo "" >> "$LESSONS_FILE"
    echo "$NEW_CANDIDATES" >> "$LESSONS_FILE"
    log "Appended $CANDIDATES_ADDED candidate(s) to editorial-lessons.md"
  fi
else
  log "No new candidates to add"
fi

# --- Step 9: Promotion / Discard / Age-out logic ---
log "--- PROMOTION: Evaluating existing candidates ---"

python3 -c "
import re, sys
from datetime import datetime, timedelta

lessons_file = '$LESSONS_FILE'
today = datetime.strptime('$TODAY', '%Y-%m-%d')
eight_weeks_ago = today - timedelta(weeks=8)

with open(lessons_file, 'r') as f:
    content = f.read()

# Parse candidate entries (lines starting with '- [YYYY-MM-DD]' in candidates section)
candidates_header = '## Candidates (promote or discard)'
if candidates_header.lower() not in content.lower():
    # Try alternate header
    for variant in ['## Candidates', '## candidates']:
        if variant.lower() in content.lower():
            candidates_header = variant
            break

lines = content.split('\n')
promotions = 0
discards = 0
aged = 0
modified_lines = []
i = 0
in_candidates = False

while i < len(lines):
    line = lines[i]

    # Detect candidates section
    if 'candidate' in line.lower() and line.startswith('## '):
        in_candidates = True
        modified_lines.append(line)
        i += 1
        continue

    if in_candidates and line.startswith('## '):
        in_candidates = False

    if not in_candidates:
        modified_lines.append(line)
        i += 1
        continue

    # Parse candidate date
    date_match = re.match(r'^- \[(\d{4}-\d{2}-\d{2})\]', line)
    if date_match:
        cand_date = datetime.strptime(date_match.group(1), '%Y-%m-%d')

        # Collect full candidate block (may span multiple lines)
        block = [line]
        j = i + 1
        while j < len(lines) and lines[j] and not lines[j].startswith('- ['):
            block.append(lines[j])
            j += 1
        block_text = '\n'.join(block)

        # Check for 5+ posts with consistent signal → promote
        evidence_match = re.search(r'(\d+)\s*posts?', block_text)
        post_count = int(evidence_match.group(1)) if evidence_match else 0

        # Check signal consistency keywords
        has_consistent = any(w in block_text.lower() for w in ['consistent', 'reliably', 'always', 'every'])
        has_inconsistent = any(w in block_text.lower() for w in ['inconsistent', 'mixed', 'neutral', 'sometimes', 'unclear'])

        if post_count >= 5 and has_consistent and not has_inconsistent:
            # PROMOTE: Add [auto-promoted] tag
            promoted_line = block[0].rstrip() + ' [auto-promoted $TODAY]'
            modified_lines.append(promoted_line)
            for bl in block[1:]:
                modified_lines.append(bl)
            promotions += 1
            print(f'PROMOTED: {block[0][:80]}', file=sys.stderr)
            i = j
            continue
        elif post_count >= 3 and has_inconsistent:
            # DISCARD: Remove the candidate
            discards += 1
            print(f'DISCARDED: {block[0][:80]}', file=sys.stderr)
            i = j
            continue
        elif cand_date < eight_weeks_ago and '[needs-review]' not in block_text:
            # AGE-OUT: Add [needs-review] tag
            aged_line = block[0].rstrip() + ' [needs-review]'
            modified_lines.append(aged_line)
            for bl in block[1:]:
                modified_lines.append(bl)
            aged += 1
            print(f'AGED: {block[0][:80]}', file=sys.stderr)
            i = j
            continue
        else:
            # Keep as-is
            for bl in block:
                modified_lines.append(bl)
            i = j
            continue
    else:
        modified_lines.append(line)
        i += 1

# Write back
with open(lessons_file, 'w') as f:
    f.write('\n'.join(modified_lines))

print(f'PROMOTIONS:{promotions} DISCARDS:{discards} AGED:{aged}', file=sys.stderr)
" 2>>"$LOG"

# Parse promotion stats from log
PROMOTIONS=$(grep -c "PROMOTED:" "$LOG" 2>/dev/null || echo "0")
DISCARDS=$(grep -c "DISCARDED:" "$LOG" 2>/dev/null || echo "0")
log "Promotion pass: $PROMOTIONS promoted, $DISCARDS discarded"

# --- Step 10: Exemplar rotation ---
log "--- EXEMPLARS: Evaluating rotation ---"

if [ -f "$EXEMPLARS_FILE" ]; then
  # Write analysis and metrics to temp files to avoid shell quoting issues
  ANALYSIS_TMPFILE=$(mktemp)
  METRICS_TMPFILE=$(mktemp)
  echo "$ANALYSIS_OUTPUT" > "$ANALYSIS_TMPFILE"
  echo "$METRICS_SUMMARY" > "$METRICS_TMPFILE"
  trap 'rm -f "$ANALYSIS_TMPFILE" "$METRICS_TMPFILE"' EXIT

  ROTATION_RESULT=$(python3 -c "
import json, sys, re
from datetime import datetime

with open('$ANALYSIS_TMPFILE', 'r') as f:
    analysis = f.read()
with open('$METRICS_TMPFILE', 'r') as f:
    metrics_summary = json.load(f)
exemplars_file = '$EXEMPLARS_FILE'
rotation_log = '$ROTATION_LOG'
today = '$TODAY'

with open(exemplars_file, 'r') as f:
    exemplars_content = f.read()

# Extract rotation suggestions from analysis
rotation_section = ''
in_section = False
for line in analysis.split('\n'):
    if '## EXEMPLAR ROTATION' in line.upper():
        in_section = True
        continue
    elif line.startswith('## ') and in_section:
        break
    elif in_section:
        rotation_section += line + '\n'

# Check if 'no rotation' is indicated
if 'no rotation needed' in rotation_section.lower():
    print('NO_ROTATION')
    sys.exit(0)

# Find measured exemplars and their engagement rates
measured_exemplars = []
sections = re.split(r'\n## ', exemplars_content)
for sec in sections:
    if '[MEASURED]' in sec:
        title_match = re.match(r'(.+?)(?:\n|$)', sec)
        title = title_match.group(1).strip() if title_match else 'Unknown'
        # Try to find engagement data in the section
        eng_match = re.search(r'(\d+\.?\d*)%\s*eng', sec)
        eng_rate = float(eng_match.group(1)) / 100 if eng_match else None
        imp_match = re.search(r'([\d,]+)\s*imp', sec)
        impressions = int(imp_match.group(1).replace(',', '')) if imp_match else 0
        measured_exemplars.append({
            'title': title,
            'engagement_rate': eng_rate,
            'impressions': impressions,
            'section_text': sec
        })

if not measured_exemplars:
    print('NO_MEASURED_EXEMPLARS')
    sys.exit(0)

# Find lowest-performing measured exemplar
measured_with_rate = [e for e in measured_exemplars if e['engagement_rate'] is not None]
if not measured_with_rate:
    print('NO_RATES_FOUND')
    sys.exit(0)

lowest = min(measured_with_rate, key=lambda x: x['engagement_rate'])

# Find highest-performing new measured post not already in exemplars
posts = metrics_summary['posts']
best_new = None
for post in sorted(posts, key=lambda x: x['engagement_rate'], reverse=True):
    if post['engagement_rate'] > (lowest['engagement_rate'] or 0):
        # Check it's not already an exemplar
        aid = str(post['activity_id'])
        if aid not in exemplars_content and post.get('file'):
            best_new = post
            break

if not best_new:
    print('NO_BETTER_POST')
    sys.exit(0)

# Count current exemplar entries
exemplar_count = len([s for s in sections if s.strip() and not s.startswith('---')])

# Perform rotation
old_title = lowest['title']
new_title = best_new.get('file', '').split('/')[-1].replace('.md', '') if best_new.get('file') else str(best_new['activity_id'])
old_rate = f\"{lowest['engagement_rate']*100:.2f}%\" if lowest['engagement_rate'] else 'unknown'
new_rate = f\"{best_new['engagement_rate']*100:.2f}%\"
reason = f'New post engagement ({new_rate}) exceeds lowest exemplar ({old_rate})'

# Build new exemplar entry from the post's content
new_entry = f\"\"\"## [MEASURED] {new_title} ({today})
- **Engagement rate:** {new_rate}
- **Impressions:** {best_new['impressions']}
- **Reactions:** {best_new['reactions']} | **Comments:** {best_new['comments']} | **Shares:** {best_new['shares']}

\"\"\"

if best_new.get('file_content'):
    # Extract hook (first ~500 chars of body after frontmatter)
    body = re.sub(r'^---.*?---\n', '', best_new['file_content'], flags=re.DOTALL)
    hook = body[:500].strip()
    new_entry += hook + '\n'

# Replace the lowest exemplar section in the file
# Find and replace the section for the lowest exemplar
old_section_pattern = re.escape('[MEASURED]') + r'.*?' + re.escape(old_title.split('(')[0].strip())
new_content = exemplars_content

# More targeted replacement: find the section by title
old_header = f'[MEASURED] {old_title}'
if old_header in new_content:
    # Find section boundaries
    start = new_content.index(old_header)
    # Go back to find '## '
    section_start = new_content.rfind('## ', 0, start)
    # Find next section
    next_section = new_content.find('\n## ', start + 1)
    next_divider = new_content.find('\n---\n', start + 1)
    if next_section == -1:
        end = len(new_content)
    elif next_divider != -1 and next_divider < next_section:
        end = next_divider
    else:
        end = next_section

    new_content = new_content[:section_start] + new_entry + '\n---\n' + new_content[end:]

    with open(exemplars_file, 'w') as f:
        f.write(new_content)

    # Write rotation log
    log_entry = f\"\"\"
## {today}
- **Removed:** {old_title} (engagement: {old_rate})
- **Added:** {new_title} (engagement: {new_rate})
- **Reason:** {reason}
\"\"\"

    if not __import__('os').path.exists(rotation_log):
        with open(rotation_log, 'w') as f:
            f.write('# Exemplar Rotation Log\\n')

    with open(rotation_log, 'a') as f:
        f.write(log_entry)

    print(f'ROTATED:{old_title}|{new_title}|{old_rate}|{new_rate}')
else:
    print('SECTION_NOT_FOUND')
" 2>>"$LOG")

  case "$ROTATION_RESULT" in
    NO_ROTATION)
      log "Exemplar rotation: not needed (Claude analysis confirms)" ;;
    NO_MEASURED_EXEMPLARS)
      log "Exemplar rotation: no measured exemplars found to compare" ;;
    NO_RATES_FOUND)
      log "Exemplar rotation: no engagement rates found in exemplars" ;;
    NO_BETTER_POST)
      log "Exemplar rotation: no new post outperforms current lowest exemplar" ;;
    SECTION_NOT_FOUND)
      log "WARNING: Could not find exemplar section to replace" ;;
    ROTATED:*)
      IFS='|' read -r old new old_rate new_rate <<< "${ROTATION_RESULT#ROTATED:}"
      log "Exemplar rotated: '$old' ($old_rate) → '$new' ($new_rate)"
      EXEMPLAR_ROTATIONS=1
      ;;
    *)
      log "Exemplar rotation result: $ROTATION_RESULT" ;;
  esac
else
  log "WARNING: Exemplars file not found — skipping rotation"
fi

# --- Step 11: Slack summary ---
log "--- SLACK: Sending retro summary ---"

TODAY_DISPLAY=$(date '+%b %-d')
SUMMARY=":bar_chart: *Weekly Content Retro — ${TODAY_DISPLAY}*\n\n"
SUMMARY+=":chart_with_upwards_trend: *Metrics Summary*\n"
SUMMARY+="• Posts analyzed: ${DEDUPED_COUNT}\n"
SUMMARY+="• Matched to files: ${MATCHED_COUNT}\n"
SUMMARY+="• Avg engagement: ${AVG_RATE}\n\n"

if [ "$CANDIDATES_ADDED" -gt 0 ]; then
  SUMMARY+=":bulb: ${CANDIDATES_ADDED} new candidate rule(s) added\n"
fi
if [ "$PROMOTIONS" -gt 0 ]; then
  SUMMARY+=":star: ${PROMOTIONS} rule(s) auto-promoted\n"
fi
if [ "$DISCARDS" -gt 0 ]; then
  SUMMARY+=":wastebasket: ${DISCARDS} candidate(s) discarded (inconsistent signal)\n"
fi
if [ "$STUBS_CREATED" -gt 0 ]; then
  SUMMARY+=":new: ${STUBS_CREATED} stub(s) created for off-pipeline posts (from LinkedIn export)\n"
fi
if [ "$EXEMPLAR_ROTATIONS" -gt 0 ]; then
  SUMMARY+=":arrows_counterclockwise: Exemplar rotation performed — see rotation log\n"
fi
if [ "$ERRORS" -gt 0 ]; then
  SUMMARY+="\n:warning: ${ERRORS} error(s) — check log: ${LOG}\n"
fi

SUMMARY+="\n:arrows_counterclockwise: Files sync to MBP within ~1 minute via Syncthing"

if [ -n "${SLACK_CONTENT_BOT_TOKEN:-}" ] && [ -n "${SLACK_CONTENT_CHANNEL_ID:-}" ]; then
  PAYLOAD=$(python3 -c "
import json, sys
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
else
  log "WARNING: SLACK_CONTENT_BOT_TOKEN or SLACK_CONTENT_CHANNEL_ID not set — skipping Slack notification"
fi

log "=== Auto-Retro Complete ==="
log "Candidates: +$CANDIDATES_ADDED | Promoted: $PROMOTIONS | Discarded: $DISCARDS | Exemplar rotations: $EXEMPLAR_ROTATIONS | Stubs: $STUBS_CREATED | Errors: $ERRORS"
