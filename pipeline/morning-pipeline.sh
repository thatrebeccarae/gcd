#!/bin/bash
# morning-pipeline.sh — runs at 6:30 AM ET on your host host
# Produces + reviews GCD drafts from sprint-assigned briefs
# Install: cp to ~/morning-pipeline.sh on your host, chmod +x
# LaunchAgent: com.gcd.morning-pipeline — runs daily at 6:30 AM ET

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
BRIEFS_DIR="$VAULT/01-Inbox/content-signals/briefs"
CONTENT_DIR="$VAULT/03-Areas/professional-content"
VOICE_GUIDE="$VAULT/09-Profile/voice-guide.md"
TODAY=$(date +%Y-%m-%d)
LOG_DIR="$VAULT/01-Inbox/pipeline-runs"
LOG="$LOG_DIR/${TODAY}-morning.log"
EXECPR_FLAGS="$VAULT/01-Inbox/content-signals/execpr-flags/${TODAY}.json"
CAMPAIGN_TRACKER="$VAULT/03-Areas/executive-pr/campaign-tracker.md"

mkdir -p "$LOG_DIR"

PRODUCED=0
REVIEWED=0
ERRORS=0
DRAFT_RESULTS=()

log() {
  echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"
}

log "=== Morning Pipeline Started ==="
log "Date: $TODAY"
log "Briefs dir: $BRIEFS_DIR"

# Check for Syncthing conflicts before processing
CONFLICTS=$(find "$CONTENT_DIR" -name "*.sync-conflict-*" 2>/dev/null | head -5)
if [ -n "$CONFLICTS" ]; then
  log "WARNING: Syncthing conflicts detected — resolve before approving:"
  echo "$CONFLICTS" | while read -r f; do log "  CONFLICT: $f"; done
fi

# --- AUTO-SPRINT-PLANNING: assign unplanned briefs if queue is empty ---
# Runs on Mondays (or any day with no sprint-assigned stubs)
# Picks top briefs by impact_score, assigns to current week
AUTO_PLANNED=0
has_sprint_stubs() {
  for brief in "$BRIEFS_DIR"/*.md; do
    [ -f "$brief" ] || continue
    local s=$(grep -m1 '^status:' "$brief" | awk '{print $2}')
    local sp=$(grep -m1 '^sprint:' "$brief" || echo "")
    [ "$s" = "stub" ] && [ -n "$sp" ] && return 0
  done
  return 1
}

if ! has_sprint_stubs; then
  log "--- AUTO-SPRINT: No sprint-assigned briefs — checking queue ---"

  # Collect unassigned stubs with their impact scores
  UNASSIGNED=()
  for brief in "$BRIEFS_DIR"/*.md; do
    [ -f "$brief" ] || continue
    s=$(grep -m1 '^status:' "$brief" | awk '{print $2}' || echo "")
    sp=$(grep -m1 '^sprint:' "$brief" || echo "")
    [ "$s" != "stub" ] && continue
    [ -n "$sp" ] && continue
    score=$(grep -m1 '^impact_score:' "$brief" | awk '{print $2}' || echo "0")
    UNASSIGNED+=("$score|$brief")
  done

  if [ ${#UNASSIGNED[@]} -gt 0 ]; then
    # Sort by impact score descending, pick top 3
    WEEK_NUM=$(date +%V)
    YEAR_NUM=$(date +%G)
    SPRINT_TAG="${YEAR_NUM}-W${WEEK_NUM}"
    PIECE_NUM=0

    SORTED=$(printf '%s\n' "${UNASSIGNED[@]}" | sort -t'|' -k1 -rn | head -3)

    while IFS='|' read -r score brief_path; do
      [ -z "$brief_path" ] && continue
      PIECE_NUM=$((PIECE_NUM + 1))
      PIECE_ID="W${WEEK_NUM}-$(printf '%02d' $PIECE_NUM)"

      # Determine scheduled date from linkedin_slot or default spacing
      slot=$(grep -m1 '^linkedin_slot:' "$brief_path" | sed 's/^linkedin_slot: //' || echo "")
      route=$(grep -m1 '^route:' "$brief_path" | awk '{print $2}' || echo "linkedin")
      matched_pillars=$(grep -m1 '^matched_pillars:' "$brief_path" | sed 's/^matched_pillars: //' || echo "")

      # Map slot day to offset from Monday (1=Mon)
      case "$slot" in
        *Monday*) DAY_OFFSET=0 ;;
        *Tuesday*) DAY_OFFSET=1 ;;
        *Wednesday*) DAY_OFFSET=2 ;;
        *Thursday*) DAY_OFFSET=3 ;;
        *Friday*) DAY_OFFSET=4 ;;
        *) DAY_OFFSET=$((PIECE_NUM)) ;;  # Default: space out by piece number
      esac

      SCHED_DATE=$(python3 -c "
from datetime import datetime, timedelta
today = datetime.now()
# Find this week's Monday
monday = today - timedelta(days=today.weekday())
target = monday + timedelta(days=$DAY_OFFSET)
# If target is in the past, push to next week
if target.date() < today.date():
    target += timedelta(days=7)
print(target.strftime('%Y-%m-%dT08:30:00-05:00'))
")
      SCHED_SHORT=$(echo "$SCHED_DATE" | cut -c1-10)

      # Derive pillar from matched_pillars for frontmatter
      pillar=$(python3 -c "
import re
mp = '$matched_pillars'
# Extract first pillar name
m = re.search(r'[A-Z][A-Za-z &]+', mp)
print(m.group(0).strip() if m else 'AI & Automation')
")

      # Update brief frontmatter with sprint assignment
      sed -i "" "s/^status: stub/status: stub\nsprint: $SPRINT_TAG\npiece_id: $PIECE_ID\npillar: $pillar\nscheduled: $SCHED_DATE/" "$brief_path"

      AUTO_PLANNED=$((AUTO_PLANNED + 1))
      log "Auto-assigned: $(basename "$brief_path") -> $PIECE_ID [$SPRINT_TAG] scheduled=$SCHED_SHORT"
    done <<< "$SORTED"

    log "Auto-sprint-planned $AUTO_PLANNED brief(s) for $SPRINT_TAG"
  else
    log "No unassigned briefs in queue — pipeline has no work"
  fi
fi

# --- Find sprint-assigned stubs scheduled within the next 3 days ---
# Produces drafts with lead time before publish date, not just today's briefs
BRIEF_FILES=()
DEADLINE=$(python3 -c "from datetime import datetime, timedelta; print((datetime.now() + timedelta(days=10)).strftime('%Y-%m-%d'))")
log "Looking for stubs scheduled before $DEADLINE"

for brief in "$BRIEFS_DIR"/*.md; do
  [ -f "$brief" ] || continue

  # Parse frontmatter fields
  status=$(grep -m1 '^status:' "$brief" | awk '{print $2}' || echo "")
  sprint=$(grep -m1 '^sprint:' "$brief" || echo "")
  route=$(grep -m1 '^route:' "$brief" | awk '{print $2}' || echo "")
  topic=$(grep -m1 '^topic:' "$brief" | sed 's/^topic: //' || echo "")
  piece_id=$(grep -m1 '^piece_id:' "$brief" | awk '{print $2}' || echo "")
  pillar=$(grep -m1 '^pillar:' "$brief" | sed 's/^pillar: //' || echo "")
  scheduled=$(grep -m1 '^scheduled:' "$brief" | awk '{print $2}' | cut -c1-10 || echo "")

  # Only process sprint-assigned stubs
  [ "$status" != "stub" ] && continue
  [ -z "$sprint" ] && continue

  # Only produce if scheduled within the next 3 days
  if [ -n "$scheduled" ] && [[ "$scheduled" > "$DEADLINE" ]]; then
    continue
  fi

  log "Found sprint-assigned brief: $(basename "$brief") [$piece_id] route=$route scheduled=$scheduled"
  BRIEF_FILES+=("$brief")
done

if [ ${#BRIEF_FILES[@]} -eq 0 ]; then
  log "No sprint-assigned briefs found for today."
  # Still check ExecPR flags and Slack below
else
  log "Processing ${#BRIEF_FILES[@]} brief(s)..."
fi

# --- Produce + Review each brief ---
DRAFT_RESULTS=()
for brief in "${BRIEF_FILES[@]+"${BRIEF_FILES[@]}"}"; do
  [ -z "$brief" ] && continue
  filename=$(basename "$brief")
  route=$(grep -m1 '^route:' "$brief" | awk '{print $2}' || echo "linkedin")
  topic=$(grep -m1 '^topic:' "$brief" | sed 's/^topic: //' || echo "unknown")
  piece_id=$(grep -m1 '^piece_id:' "$brief" | awk '{print $2}' || echo "")
  pillar=$(grep -m1 '^pillar:' "$brief" | sed 's/^pillar: //' || echo "")

  # Determine output path based on route — all content goes to content/YYYY/
  # Use the brief's scheduled date for the filename, not today's date
  SCHEDULED_DATE=$(echo "$scheduled" | cut -c1-10)
  if [ -z "$SCHEDULED_DATE" ]; then
    SCHEDULED_DATE="$TODAY"
  fi
  YEAR=$(echo "$SCHEDULED_DATE" | cut -c1-4)
  case "$route" in
    linkedin) PREFIX="LI" ;;
    essay) PREFIX="SS" ;;
    twitter-thread) PREFIX="TW" ;;
    *) PREFIX="LI" ;;
  esac
  SLUG=$(echo "$topic" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')
  OUTPUT_DIR="$CONTENT_DIR/content/$YEAR"
  OUTPUT_FILE="$OUTPUT_DIR/${SCHEDULED_DATE}-${PREFIX}-${SLUG}.md"

  mkdir -p "$OUTPUT_DIR"
  log "--- PRODUCE: $filename -> $OUTPUT_FILE ---"

  # --- Read brief, voice guide, lessons, and exemplar content for prompt ---
  BRIEF_CONTENT=$(cat "$brief")
  VOICE_CONTENT=$(cat "$VOICE_GUIDE")
  SPRINT_VAL=$(grep -m1 '^sprint:' "$brief" | sed 's/^sprint: //' || echo "")
  SCHEDULED_VAL=$(grep -m1 '^scheduled:' "$brief" | sed 's/^scheduled: //' || echo "")

  # Map route to exemplar filename
  case "$route" in
    linkedin) EXEMPLAR_ROUTE="linkedin" ;;
    essay) EXEMPLAR_ROUTE="essay" ;;
    twitter-thread) EXEMPLAR_ROUTE="twitter-thread" ;;
    *) EXEMPLAR_ROUTE="linkedin" ;;
  esac

  # Pre-compute frontmatter fields for prompt template
  case "$route" in
    linkedin) PLATFORM="linkedin" ;; essay) PLATFORM="substack" ;; twitter-thread) PLATFORM="twitter" ;; *) PLATFORM="linkedin" ;;
  esac
  case "$route" in
    essay) CONTENT_TYPE="insight" ;; *) CONTENT_TYPE="social" ;;
  esac
  BRIEF_SLUG=$(basename "$brief" .md)

  LESSONS_FILE="$VAULT/03-Areas/professional-content/strategy/editorial-lessons.md"
  EXEMPLAR_FILE="$VAULT/03-Areas/professional-content/strategy/exemplars/${EXEMPLAR_ROUTE}.md"

  LESSONS_CONTENT=""
  [ -f "$LESSONS_FILE" ] && LESSONS_CONTENT=$(cat "$LESSONS_FILE")

  VOICE_DRIFT_FILE="$VAULT/03-Areas/professional-content/strategy/voice-drift.md"
  VOICE_DRIFT_CONTENT=""
  [ -f "$VOICE_DRIFT_FILE" ] && VOICE_DRIFT_CONTENT=$(cat "$VOICE_DRIFT_FILE")

  EXEMPLAR_CONTENT=""
  if [ -f "$EXEMPLAR_FILE" ]; then
    EXEMPLAR_CONTENT=$(cat "$EXEMPLAR_FILE")
    # Truncate essay exemplars if > 15KB (keep first 1000 chars per entry)
    if [ "$EXEMPLAR_ROUTE" = "essay" ]; then
      FILE_SIZE=$(wc -c < "$EXEMPLAR_FILE" | tr -d ' ')
      if [ "$FILE_SIZE" -gt 15360 ]; then
        EXEMPLAR_CONTENT=$(python3 -c "
import sys
content = sys.stdin.read()
entries = content.split('\n---\n')
truncated = []
for entry in entries:
  if len(entry) > 1000:
    truncated.append(entry[:1000] + '\n[...truncated...]')
  else:
    truncated.append(entry)
print('\n---\n'.join(truncated))
" <<< "$EXEMPLAR_CONTENT")
      fi
    fi
  fi

  # --- PRODUCE → REVIEW LOOP (max 3 attempts) ---
  MAX_ATTEMPTS=3
  ATTEMPT=0
  REVIEW_DECISION="revise"

  while [ "$REVIEW_DECISION" != "pass" ] && [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))

    if [ $ATTEMPT -eq 1 ]; then
      # --- INITIAL DRAFT ---
      log "--- PRODUCE (attempt $ATTEMPT): $filename ---"
      PRODUCE_PROMPT="You are a content producer for Your Name's professional content pipeline.

BRIEF:
$BRIEF_CONTENT

VOICE GUIDE:
$VOICE_CONTENT

EDITORIAL LESSONS (follow every rule):
$LESSONS_CONTENT

VOICE DRIFT PATTERNS (apply promoted rules, consider candidates):
$VOICE_DRIFT_CONTENT

EXEMPLARS (study patterns, do not copy):
$EXEMPLAR_CONTENT

Produce a draft following these rules:
- Route: $route
- If linkedin: Write a LinkedIn post (800-1200 chars body). Hook in first 2 lines. Line breaks for readability. End with question or CTA. 3-5 hashtags.
- If essay: Write a Substack essay (1500-3000 words). Include data/examples from key articles. Personal angle + industry analysis.
- If twitter-thread: Write a Twitter thread (3-8 tweets, 280 chars each). Hook tweet must stand alone.

CRITICAL VOICE RULES:
- Observe before prescribing — react to specific news, don't lecture
- Details over generalities — name the tool, the moment, the specific experience
- Never preachy. If it sounds like a TED talk, rewrite it.
- The bialetti, not 'coffee' — sensory specificity makes it yours

Output ONLY the complete draft file content starting with frontmatter. No commentary, no code fences, no summary. Start with ---.

Use this frontmatter:
---
title: [a specific, tension-driven title — NOT an abstract noun phrase]
piece_id: $piece_id
pillar: $pillar
route: $route
status: draft
created: $TODAY
sprint: $SPRINT_VAL
scheduled: $SCHEDULED_VAL
platform: $PLATFORM
context: professional
type: $CONTENT_TYPE
brief_slug: $BRIEF_SLUG
---"

      DRAFT_OUTPUT=$(claude --print -p "$PRODUCE_PROMPT" 2>>"$LOG")
      CLAUDE_EXIT=$?

      if [ $CLAUDE_EXIT -ne 0 ] || [ -z "$DRAFT_OUTPUT" ]; then
        log "ERROR: Draft production failed for $filename (exit: $CLAUDE_EXIT)"
        ERRORS=$((ERRORS + 1))
        break
      fi
    else
      # --- REVISION from review feedback ---
      log "--- REVISE (attempt $ATTEMPT): $(basename "$OUTPUT_FILE") ---"
      CURRENT_DRAFT=$(cat "$OUTPUT_FILE")

      REVISE_PROMPT="You are revising a draft for Your Name's content pipeline. The editor reviewed it and marked it 'revise'.

CURRENT DRAFT (with editor's inline <!-- REVIEW: ... --> comments):
$CURRENT_DRAFT

VOICE GUIDE:
$VOICE_CONTENT

EDITORIAL LESSONS (follow every rule):
$LESSONS_CONTENT

VOICE DRIFT PATTERNS (apply promoted rules, consider candidates):
$VOICE_DRIFT_CONTENT

EXEMPLARS (study patterns, do not copy):
$EXEMPLAR_CONTENT

ORIGINAL BRIEF:
$BRIEF_CONTENT

Apply ALL the editor's review comments. Remove every <!-- REVIEW: ... --> comment after addressing it. The revised draft must:
- Fix every issue the editor flagged
- Stay within platform constraints ($route)
- Sound like Your Name — direct, specific, observational, never preachy

Output ONLY the revised file content starting with ---. No commentary, no code fences. Update status to 'draft' in frontmatter."

      DRAFT_OUTPUT=$(claude --print -p "$REVISE_PROMPT" 2>>"$LOG")
      CLAUDE_EXIT=$?

      if [ $CLAUDE_EXIT -ne 0 ] || [ -z "$DRAFT_OUTPUT" ]; then
        log "ERROR: Revision failed for $filename attempt $ATTEMPT (exit: $CLAUDE_EXIT)"
        ERRORS=$((ERRORS + 1))
        break
      fi
    fi

    # Write draft (strip code fences if present, using Python for macOS compat)
    python3 -c "
import sys, re
content = sys.stdin.read()
content = re.sub(r'^\`\`\`\w*\n', '', content)
content = re.sub(r'\n\`\`\`\s*$', '', content)
# Strip leading blank lines before frontmatter
content = content.lstrip('\n')
sys.stdout.write(content)
" <<< "$DRAFT_OUTPUT" > "$OUTPUT_FILE"

    log "Draft written to: $OUTPUT_FILE ($(wc -c < "$OUTPUT_FILE" | tr -d ' ') bytes)"
    if [ $ATTEMPT -eq 1 ]; then
      PRODUCED=$((PRODUCED + 1))
    fi

    # --- EDITORIAL REVIEW ---
    log "--- REVIEW (attempt $ATTEMPT): $(basename "$OUTPUT_FILE") ---"
    DRAFT_CONTENT=$(cat "$OUTPUT_FILE")

    REVIEW_PROMPT="You are an editorial reviewer for Your Name's content pipeline.

DRAFT:
$DRAFT_CONTENT

VOICE GUIDE:
$VOICE_CONTENT

EDITORIAL LESSONS (follow every rule):
$LESSONS_CONTENT

EXEMPLARS (study patterns, do not copy):
$EXEMPLAR_CONTENT

ORIGINAL BRIEF:
$BRIEF_CONTENT

Review the draft on these criteria:
1. Hook grade (A/B/C/D) — does the opening stop the scroll?
2. Voice match — does it sound like Your Name (direct, builder-operator, specific, NEVER preachy)?
3. Structure — clear flow, appropriate length for route ($route)?
4. Argument quality — specific claims backed by evidence/experience?
5. CTA effectiveness — does it drive engagement?

DECISION: If the draft meets quality bar on ALL criteria, output DECISION:pass. If ANY criterion fails, output DECISION:revise and add inline <!-- REVIEW: ... --> comments where fixes are needed.

IMPORTANT: Your output must follow this EXACT format — nothing else:
Line 1: DECISION:pass or DECISION:revise
Line 2: (blank)
Line 3 onward: The complete file content starting with --- (the frontmatter delimiter)

If pass: set 'status: reviewed' and 'review_decision: pass' in frontmatter.
If revise: set 'review_decision: revise' in frontmatter and add <!-- REVIEW: ... --> comments inline.

Do NOT include markdown code fences, summary tables, or any text after the file content."

    REVIEW_OUTPUT=$(claude --print -p "$REVIEW_PROMPT" 2>>"$LOG")
    REVIEW_EXIT=$?

    if [ $REVIEW_EXIT -ne 0 ] || [ -z "$REVIEW_OUTPUT" ]; then
      log "ERROR: Review failed for $(basename "$OUTPUT_FILE") attempt $ATTEMPT (exit: $REVIEW_EXIT)"
      ERRORS=$((ERRORS + 1))
      REVIEW_DECISION="error"
      break
    fi

    # Extract decision and write file (Python for macOS compat)
    REVIEW_DECISION=$(python3 -c "
import sys, re
text = sys.stdin.read()
first_line = text.split('\n')[0]
m = re.search(r'DECISION:(\w+)', first_line)
print(m.group(1) if m else 'unknown')
" <<< "$REVIEW_OUTPUT")

    python3 -c "
import sys
lines = sys.stdin.read().split('\n')
# Skip DECISION line and any blank lines after it
start = 1
while start < len(lines) and not lines[start].strip():
    start += 1
sys.stdout.write('\n'.join(lines[start:]))
" <<< "$REVIEW_OUTPUT" > "$OUTPUT_FILE"

    log "Review attempt $ATTEMPT — decision: $REVIEW_DECISION"
    REVIEWED=$((REVIEWED + 1))
  done

  if [ "$REVIEW_DECISION" != "pass" ] && [ $ATTEMPT -ge $MAX_ATTEMPTS ]; then
    log "WARNING: Max review attempts ($MAX_ATTEMPTS) reached for $filename — last decision: $REVIEW_DECISION"
  fi

  # Update brief status so future runs skip it
  sed -i "" "s/^status: stub/status: draft/" "$brief"
  log "Brief status updated to 'draft': $filename"

  # Snapshot GCD draft for voice-diff learning (before human edits)
  DRAFT_SNAPSHOT="${OUTPUT_FILE%.md}.draft.md"
  cp "$OUTPUT_FILE" "$DRAFT_SNAPSHOT"
  log "Draft snapshot saved: $(basename "$DRAFT_SNAPSHOT")"

  DRAFT_RESULTS+=("$piece_id|$pillar|$REVIEW_DECISION|$OUTPUT_FILE|$filename")
done

# --- EXECPR FLAGS PROCESSING ---
EXECPR_COUNT=0
if [ -f "$EXECPR_FLAGS" ]; then
  EXECPR_COUNT=$(python3 -c "import json; print(len(json.load(open('$EXECPR_FLAGS'))))" 2>/dev/null || echo "0")
  if [ "$EXECPR_COUNT" -gt 0 ]; then
    log "--- EXECPR: Processing $EXECPR_COUNT flags ---"

    FLAGS_CONTENT=$(cat "$EXECPR_FLAGS")
    TRACKER_CONTENT=""
    [ -f "$CAMPAIGN_TRACKER" ] && TRACKER_CONTENT=$(cat "$CAMPAIGN_TRACKER")

    EXECPR_PROMPT="You are processing ExecPR opportunity flags for Your Name's campaign tracker.

EXISTING CAMPAIGN TRACKER:
$TRACKER_CONTENT

NEW FLAGS (JSON):
$FLAGS_CONTENT

For each opportunity in the JSON array, output a markdown entry in this format:

## [Topic] — [Type]
- **Status:** identified
- **Date flagged:** $TODAY
- **Strategy fit:** [score]/10
- **Source:** DFI auto-flag
- **Articles:** [list article titles with URLs]
- **Rationale:** [from flags]
- **Suggested action:** [from flags]
---

RULES:
- Skip any opportunity whose topic already appears in the existing tracker above.
- Output ONLY the new markdown entries. No commentary, no code fences.
- If all opportunities are duplicates, output nothing."

    EXECPR_OUTPUT=$(claude --print -p "$EXECPR_PROMPT" 2>>"$LOG")
    if [ $? -eq 0 ] && [ -n "$EXECPR_OUTPUT" ]; then
      # Create tracker with header if it doesn't exist
      if [ ! -f "$CAMPAIGN_TRACKER" ]; then
        echo "# ExecPR Campaign Tracker" > "$CAMPAIGN_TRACKER"
      fi
      echo "" >> "$CAMPAIGN_TRACKER"
      echo "$EXECPR_OUTPUT" >> "$CAMPAIGN_TRACKER"
      log "ExecPR flags processed — appended to campaign tracker"
    else
      log "ERROR: ExecPR processing failed or no new entries"
      ERRORS=$((ERRORS + 1))
    fi
  fi
fi

# --- WEEKLY EXECPR SCAN (Mondays only) ---
EXECPR_SCAN_COUNT=0
DAY_OF_WEEK=$(date +%u)
if [ "$DAY_OF_WEEK" -eq 1 ]; then
  log "--- EXECPR SCAN: Monday — running weekly opportunity scan ---"

  CORE_POSITIONING="$VAULT/03-Areas/executive-pr/narratives/core-positioning.md"
  CORE_POS_CONTENT=""
  [ -f "$CORE_POSITIONING" ] && CORE_POS_CONTENT=$(cat "$CORE_POSITIONING")

  TRACKER_CONTENT=""
  [ -f "$CAMPAIGN_TRACKER" ] && TRACKER_CONTENT=$(cat "$CAMPAIGN_TRACKER")

  SCAN_PROMPT="You are an executive PR strategist scanning for opportunities for Your Name.

CORE POSITIONING:
$CORE_POS_CONTENT

CURRENT CAMPAIGN TRACKER (avoid duplicates):
$TRACKER_CONTENT

Scan for new opportunities across these categories:
1. Awards — marketing, AI, ecommerce, women-in-tech awards accepting nominations
2. Podcasts — marketing/ecommerce/AI/leadership podcasts accepting guests
3. Conferences — upcoming CFPs for relevant conferences
4. Press — trending topics where Your Name can contribute expertise

For each opportunity, score on:
- Positioning Fit (1-5, 30% weight)
- Audience Reach (1-5, 20% weight)
- AEO Impact (1-5, 20% weight)
- Effort Required (1-5 inverse, 15% weight)
- Timeliness (1-5, 15% weight)

Output ONLY new campaign tracker entries in this format (no commentary, no code fences):

## [Topic/Opportunity] — [Type: award|podcast|conference|press]
- **Status:** identified
- **Date flagged:** $TODAY
- **Weighted score:** [calculated score]/5.0
- **Source:** weekly-scan
- **Positioning fit:** [score]/5
- **Audience reach:** [score]/5
- **AEO impact:** [score]/5 ([high/medium/low] — [reason])
- **Effort:** [score]/5
- **Timeliness:** [score]/5
- **Deadline:** [if known]
- **Rationale:** [why this is a fit]
- **Suggested action:** [specific next step]
---

Skip opportunities already in the campaign tracker. If no new opportunities found, output nothing."

  SCAN_OUTPUT=$(claude --print -p "$SCAN_PROMPT" 2>>"$LOG")
  if [ $? -eq 0 ] && [ -n "$SCAN_OUTPUT" ]; then
    if [ ! -f "$CAMPAIGN_TRACKER" ]; then
      echo "# ExecPR Campaign Tracker" > "$CAMPAIGN_TRACKER"
    fi
    echo "" >> "$CAMPAIGN_TRACKER"
    echo "<!-- Weekly scan: $TODAY -->" >> "$CAMPAIGN_TRACKER"
    echo "$SCAN_OUTPUT" >> "$CAMPAIGN_TRACKER"
    EXECPR_SCAN_COUNT=$(echo "$SCAN_OUTPUT" | grep -c "^## " || echo "0")
    log "ExecPR scan complete — $EXECPR_SCAN_COUNT new opportunities identified"

    # --- AUTO-DRAFT PITCHES for identified opportunities ---
    PITCH_DRAFTS_DIR="$VAULT/03-Areas/executive-pr/pitches/drafts"
    mkdir -p "$PITCH_DRAFTS_DIR"
    PITCH_COUNT=0

    # Re-read tracker to include scan results
    UPDATED_TRACKER=$(cat "$CAMPAIGN_TRACKER")

    # Extract identified opportunities (from both flags and scan)
    IDENTIFIED=$(python3 -c "
import re, sys
content = sys.stdin.read()
entries = re.split(r'\n## ', content)
identified = []
for e in entries:
    if '**Status:** identified' in e:
        title_match = re.match(r'(.+?)(?:\n|$)', e)
        if title_match:
            identified.append(title_match.group(1).strip())
for t in identified:
    print(t)
" <<< "$UPDATED_TRACKER" 2>/dev/null)

    if [ -n "$IDENTIFIED" ]; then
      while IFS= read -r opportunity; do
        # Generate slug for filename
        OPP_SLUG=$(echo "$opportunity" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')
        PITCH_FILE="$PITCH_DRAFTS_DIR/${TODAY}-${OPP_SLUG}.md"

        # Skip if pitch already exists
        [ -f "$PITCH_FILE" ] && continue

        # Determine pitch type from opportunity name
        PITCH_TYPE=$(echo "$opportunity" | grep -oi 'podcast\|award\|conference\|press' | head -1 || echo "press")
        PITCH_TEMPLATE_DIR="$VAULT/03-Areas/executive-pr/pitch-templates"
        TEMPLATE_CONTENT=""
        case "$PITCH_TYPE" in
          podcast) [ -f "$PITCH_TEMPLATE_DIR/podcast-pitch.md" ] && TEMPLATE_CONTENT=$(cat "$PITCH_TEMPLATE_DIR/podcast-pitch.md") ;;
          press) [ -f "$PITCH_TEMPLATE_DIR/press-pitch.md" ] && TEMPLATE_CONTENT=$(cat "$PITCH_TEMPLATE_DIR/press-pitch.md") ;;
          *) [ -f "$PITCH_TEMPLATE_DIR/press-pitch.md" ] && TEMPLATE_CONTENT=$(cat "$PITCH_TEMPLATE_DIR/press-pitch.md") ;;
        esac

        PITCH_PROMPT="You are drafting an executive PR pitch for Your Name.

CORE POSITIONING:
$CORE_POS_CONTENT

PITCH TEMPLATE:
$TEMPLATE_CONTENT

OPPORTUNITY: $opportunity

Write a complete pitch draft following the template structure. Personalize it for this specific opportunity. Include:
- Subject line
- Pitch body with Your Name's relevant credentials and angle
- Why now / news hook
- Proposed topics or segments

Output ONLY the pitch content starting with frontmatter. No commentary, no code fences.

---
title: Pitch — $opportunity
status: drafted
type: $PITCH_TYPE
created: $TODAY
opportunity: $opportunity
---"

        PITCH_OUTPUT=$(claude --print -p "$PITCH_PROMPT" 2>>"$LOG")
        if [ $? -eq 0 ] && [ -n "$PITCH_OUTPUT" ]; then
          echo "$PITCH_OUTPUT" > "$PITCH_FILE"
          PITCH_COUNT=$((PITCH_COUNT + 1))
          log "Draft pitch written: $(basename "$PITCH_FILE")"

          # Update campaign tracker status to drafted
          sed -i "" "s/\(## ${opportunity}\)/\1/" "$CAMPAIGN_TRACKER"
          python3 -c "
import re, sys
content = open('$CAMPAIGN_TRACKER').read()
# Find this opportunity's entry and update status
pattern = re.escape('## $opportunity')
# Replace first 'identified' after the matching header
parts = content.split('## ')
for i, part in enumerate(parts):
    if part.startswith('$(echo "$opportunity" | sed "s/'/\\\\'/g")'):
        parts[i] = part.replace('**Status:** identified', '**Status:** drafted', 1)
        break
open('$CAMPAIGN_TRACKER', 'w').write('## '.join(parts))
" 2>>"$LOG" || true
        fi
      done <<< "$IDENTIFIED"
      log "Auto-drafted $PITCH_COUNT pitch(es)"
    fi
  else
    log "ExecPR scan returned no results or failed"
  fi
else
  log "Not Monday (day $DAY_OF_WEEK) — skipping ExecPR scan"
fi

# --- SLACK SUMMARY NOTIFICATION ---
log "--- SLACK: Sending summary ---"

TODAY_DISPLAY=$(date '+%b %-d')
SUMMARY=":white_check_mark: *Morning Pipeline Complete — ${TODAY_DISPLAY}*\n"
SUMMARY+="${PRODUCED} draft(s) produced, ${REVIEWED} reviewed\n"
if [ "$AUTO_PLANNED" -gt 0 ]; then
  SUMMARY+=":calendar: Auto-sprint-planned ${AUTO_PLANNED} brief(s)\n"
fi
SUMMARY+="\n"

if [ ${#DRAFT_RESULTS[@]} -gt 0 ]; then
  SUMMARY+=":page_facing_up: *Drafts:*\n"
  for result in "${DRAFT_RESULTS[@]}"; do
    IFS='|' read -r pid pname decision draft_path brief_name <<< "$result"
    # Obsidian deep links
    draft_rel=$(echo "$draft_path" | sed "s|$VAULT/||")
    brief_rel="01-Inbox/content-signals/briefs/$brief_name"
    draft_encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$draft_rel', safe='/'))")
    brief_encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$brief_rel', safe='/'))")
    draft_link="obsidian://open?vault=your-vault&file=${draft_encoded}"
    brief_link="obsidian://open?vault=your-vault&file=${brief_encoded}"

    if [ "$decision" = "pass" ]; then
      SUMMARY+="\\u2022 :white_check_mark: ${pid} _${pname}_ — *ready for approval*\n"
      SUMMARY+="  Run \`/gcd:approve ${pid}\` to publish\n"
    else
      SUMMARY+="\\u2022 :eyes: ${pid} _${pname}_ — *needs manual review* (${decision})\n"
    fi
    SUMMARY+="  Draft: <${draft_link}|$(basename "$draft_path")>\n"
    SUMMARY+="  Brief: <${brief_link}|${brief_name}>\n"
  done
  SUMMARY+="\n"
fi

if [ "$EXECPR_COUNT" -gt 0 ]; then
  SUMMARY+=":brain: ExecPR flags: ${EXECPR_COUNT} opportunities added to campaign tracker\n"
fi

if [ "$EXECPR_SCAN_COUNT" -gt 0 ]; then
  SUMMARY+=":mag: ExecPR scan: ${EXECPR_SCAN_COUNT} new opportunities identified"
  if [ "${PITCH_COUNT:-0}" -gt 0 ]; then
    SUMMARY+=", ${PITCH_COUNT} draft pitch(es) generated"
  fi
  SUMMARY+="\n"
fi

if [ "$ERRORS" -gt 0 ]; then
  SUMMARY+=":warning: ${ERRORS} error(s) — check log: ${LOG}\n\n"
fi

SUMMARY+=":arrows_counterclockwise: Files sync to MBP within ~1 minute via Syncthing"

# Post to Slack (requires SLACK_CONTENT_BOT_TOKEN and SLACK_CONTENT_CHANNEL_ID env vars)
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

log "=== Morning Pipeline Complete ==="
log "Produced: $PRODUCED | Reviewed: $REVIEWED | Errors: $ERRORS | ExecPR flags: $EXECPR_COUNT | ExecPR scan: $EXECPR_SCAN_COUNT"
