#!/bin/bash
# voice-diff-analysis.sh — runs weekly (Sunday 8 PM) on your host host
# Compares GCD-drafted content (.draft.md) vs human-edited published versions
# to detect voice drift patterns and feed the learning loop.
# Install: cp to ~/voice-diff-analysis.sh on your host, chmod +x
# LaunchAgent: com.gcd.voice-diff — runs Sunday at 20:00

set -euo pipefail

# --- Environment ---
export PATH="~/.local/bin:~/.nvm/versions/node/v22.22.0/bin:$PATH"
# Source Docker .env for any shared env vars
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
VOICE_DRIFT_FILE="$STRATEGY_DIR/voice-drift.md"
TODAY=$(date +%Y-%m-%d)
LOG_DIR="$VAULT/01-Inbox/pipeline-runs"
LOG="$LOG_DIR/${TODAY}-voice-diff.log"

mkdir -p "$LOG_DIR"

log() {
  echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"
}

log "=== Voice Diff Analysis Started ==="
log "Date: $TODAY"

# --- Find .draft.md pairs ---
# A pair is: YYYY-MM-DD-PREFIX-slug.draft.md (GCD output) + YYYY-MM-DD-PREFIX-slug.md (human-edited)
# Only analyze pairs where the main file has status: published or measured (human has finalized it)

MATCHED_PAIRS=$(python3 << 'PYEOF'
import json
import os
import glob
import re

vault = os.environ.get("VAULT", "~/your-vault")
content_dir = os.path.join(vault, "03-Areas", "professional-content", "content")

def parse_frontmatter(filepath):
    """Return (frontmatter_dict, body_text) from a markdown file."""
    try:
        with open(filepath, "r") as f:
            text = f.read()
    except Exception:
        return {}, ""
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n(.*)", text, re.DOTALL)
    if not m:
        return {}, text
    fm_text = m.group(1)
    body = m.group(2).strip()
    fm = {}
    for line in fm_text.split("\n"):
        if ":" in line:
            key, _, val = line.partition(":")
            fm[key.strip()] = val.strip().strip('"').strip("'")
    return fm, body

# Find all .draft.md files
draft_files = glob.glob(os.path.join(content_dir, "**", "*.draft.md"), recursive=True)

matched = []
for draft_path in draft_files:
    # The main file is the same path without .draft
    main_path = draft_path.replace(".draft.md", ".md")
    if not os.path.exists(main_path):
        continue

    main_fm, main_body = parse_frontmatter(main_path)
    draft_fm, draft_body = parse_frontmatter(draft_path)

    if not main_body or not draft_body:
        continue

    # Only analyze if human has finalized (published or measured)
    status = main_fm.get("status", "")
    if status not in ("published", "measured"):
        continue

    # Skip if bodies are identical (no human edits)
    if draft_body.strip() == main_body.strip():
        continue

    matched.append({
        "draftFile": draft_path,
        "publishedFile": main_path,
        "pieceId": main_fm.get("piece_id", os.path.basename(main_path)),
        "pillar": main_fm.get("pillar", ""),
        "platform": main_fm.get("platform", ""),
        "draftBody": draft_body[:4000],
        "publishedBody": main_body[:4000]
    })

print(json.dumps(matched))
PYEOF
)

MATCH_COUNT=$(python3 -c "import json, sys; print(len(json.loads(sys.stdin.read())))" <<< "$MATCHED_PAIRS")
log "Found $MATCH_COUNT draft-to-published pairs with human edits"

if [ "$MATCH_COUNT" -lt 3 ]; then
  log "Need at least 3 pairs for meaningful diff analysis (have $MATCH_COUNT). Skipping diff pass."
fi

# --- Find rejected drafts for anti-pattern learning ---
REJECTED_DRAFTS=$(python3 << 'PYEOF'
import json
import os
import glob
import re

vault = os.environ.get("VAULT", "~/your-vault")
content_dir = os.path.join(vault, "03-Areas", "professional-content", "content")

def parse_frontmatter(filepath):
    """Return (frontmatter_dict, body_text) from a markdown file."""
    try:
        with open(filepath, "r") as f:
            text = f.read()
    except Exception:
        return {}, ""
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n(.*)", text, re.DOTALL)
    if not m:
        return {}, text
    fm_text = m.group(1)
    body = m.group(2).strip()
    fm = {}
    for line in fm_text.split("\n"):
        if ":" in line:
            key, _, val = line.partition(":")
            fm[key.strip()] = val.strip().strip('"').strip("'")
    return fm, body

# Find content files with status: rejected that have a .draft.md sibling
rejected = []
for year_dir in glob.glob(os.path.join(content_dir, "*")):
    if not os.path.isdir(year_dir):
        continue
    for fpath in glob.glob(os.path.join(year_dir, "*.md")):
        if fpath.endswith(".draft.md"):
            continue
        fm, body = parse_frontmatter(fpath)
        if fm.get("status") != "rejected":
            continue

        # Check for .draft.md sibling
        draft_path = fpath.replace(".md", ".draft.md")
        if not os.path.exists(draft_path):
            continue

        draft_fm, draft_body = parse_frontmatter(draft_path)
        if not draft_body:
            continue

        rejected.append({
            "file": fpath,
            "draftFile": draft_path,
            "pieceId": fm.get("piece_id", os.path.basename(fpath)),
            "pillar": fm.get("pillar", ""),
            "platform": fm.get("platform", ""),
            "rejectionReason": fm.get("rejection_reason", ""),
            "draftBody": draft_body[:4000]
        })

print(json.dumps(rejected))
PYEOF
)

REJECTED_COUNT=$(python3 -c "import json, sys; print(len(json.loads(sys.stdin.read())))" <<< "$REJECTED_DRAFTS")
log "Found $REJECTED_COUNT rejected drafts with .draft.md snapshots"

# Gate: need at least 3 pairs OR at least 1 rejected draft to proceed
if [ "$MATCH_COUNT" -lt 3 ] && [ "$REJECTED_COUNT" -eq 0 ]; then
  log "Not enough data for any analysis. Exiting gracefully."
  log "=== Voice Diff Analysis Complete (insufficient data) ==="
  exit 0
fi

# --- Send matched pairs to Claude for voice diff analysis (if enough pairs) ---
ANALYSIS_OUTPUT=""
if [ "$MATCH_COUNT" -ge 3 ]; then
log "Sending $MATCH_COUNT pairs to Claude for analysis..."

PAIRS_TEXT=$(python3 -c "
import json, sys

pairs = json.loads(sys.stdin.read())
output = []
for i, pair in enumerate(pairs, 1):
    output.append(f'--- PAIR {i} (piece: {pair[\"pieceId\"]}, pillar: {pair[\"pillar\"]}, platform: {pair[\"platform\"]}) ---')
    output.append(f'GCD DRAFT:')
    output.append(pair['draftBody'])
    output.append(f'')
    output.append(f'PUBLISHED (after human edits):')
    output.append(pair['publishedBody'])
    output.append(f'')
print('\n'.join(output))
" <<< "$MATCHED_PAIRS")

ANALYSIS_PROMPT="Compare these GCD-draft → human-published pairs. The DRAFT is what the AI content pipeline produced. The PUBLISHED is what Your Name actually posted after her edits. Identify systematic voice edits Your Name makes — patterns in how she changes the AI output.

Group findings by pattern type:
- **Word choice** — words/phrases she consistently swaps or removes
- **Structure** — how she restructures sentences or paragraphs
- **Tone** — shifts in formality, directness, warmth, humor
- **Specificity** — where she adds or removes detail
- **Openings** — how she changes hooks/intros
- **Closings** — how she changes CTAs/endings
- **Deletions** — what she consistently cuts (filler, hedging, transitions, etc.)
- **Additions** — what she consistently adds that the AI missed

For each pattern:
1. Describe the pattern clearly as an actionable rule (e.g., 'ALWAYS do X' or 'NEVER do Y')
2. Show 1-2 before/after examples (quote directly from the pairs)
3. Count how many pairs exhibit this pattern (frequency: X/$MATCH_COUNT)

Be specific and actionable. These patterns will be fed back into the AI content pipeline to improve future drafts.

PAIRS:
$PAIRS_TEXT"

ANALYSIS_OUTPUT=$(claude --print -p "$ANALYSIS_PROMPT" 2>>"$LOG")
CLAUDE_EXIT=$?

if [ $CLAUDE_EXIT -ne 0 ] || [ -z "$ANALYSIS_OUTPUT" ]; then
  log "ERROR: Claude analysis failed (exit: $CLAUDE_EXIT)"
  log "=== Voice Diff Analysis Complete (error) ==="
  exit 1
fi

log "Analysis received ($(echo "$ANALYSIS_OUTPUT" | wc -c | tr -d ' ') bytes)"
fi  # end MATCH_COUNT >= 3 block

# --- Anti-pattern analysis from rejected drafts ---
ANTI_PATTERN_OUTPUT=""
if [ "$REJECTED_COUNT" -gt 0 ]; then
  log "Sending $REJECTED_COUNT rejected draft(s) to Claude for anti-pattern analysis..."

  REJECTED_TEXT=$(python3 -c "
import json, sys

rejected = json.loads(sys.stdin.read())
output = []
for i, r in enumerate(rejected, 1):
    output.append(f'--- REJECTED DRAFT {i} (piece: {r[\"pieceId\"]}, pillar: {r[\"pillar\"]}, platform: {r[\"platform\"]}) ---')
    if r['rejectionReason']:
        output.append(f'REJECTION REASON: {r[\"rejectionReason\"]}')
    output.append(f'DRAFT CONTENT (what the AI produced):')
    output.append(r['draftBody'])
    output.append('')
print('\n'.join(output))
" <<< "$REJECTED_DRAFTS")

  ANTI_PATTERN_PROMPT="These are content drafts that Your Name's AI pipeline produced but she REJECTED ENTIRELY — not revised, not edited, just thrown away. They represent failures the pipeline should learn from.

Analyze what went wrong in each draft. Extract anti-patterns — things the AI did that made these drafts unsalvageable.

Group findings by failure type:
- **Topic/angle failures** — wrong framing, too generic, missed the point
- **Voice failures** — sounded too corporate, too preachy, too generic, not like Your Name
- **Structure failures** — wrong format, bad pacing, weak hooks
- **Content failures** — shallow analysis, obvious points, no original insight

For each anti-pattern:
1. State it as a clear NEVER rule (e.g., 'NEVER open with a rhetorical question about change')
2. Quote the specific failing passage from the rejected draft
3. Explain WHY it fails (what makes it unsalvageable vs just needing edits)

These anti-patterns will be fed back into the pipeline to prevent similar failures.

REJECTED DRAFTS:
$REJECTED_TEXT"

  ANTI_PATTERN_OUTPUT=$(claude --print -p "$ANTI_PATTERN_PROMPT" 2>>"$LOG")
  ANTI_CLAUDE_EXIT=$?

  if [ $ANTI_CLAUDE_EXIT -ne 0 ] || [ -z "$ANTI_PATTERN_OUTPUT" ]; then
    log "WARNING: Anti-pattern analysis failed (exit: $ANTI_CLAUDE_EXIT)"
    ANTI_PATTERN_OUTPUT=""
  else
    log "Anti-pattern analysis received ($(echo "$ANTI_PATTERN_OUTPUT" | wc -c | tr -d ' ') bytes)"
  fi
fi

# --- Build voice-drift.md with tiered sections ---
EXISTING_PROMOTED=""
if [ -f "$VOICE_DRIFT_FILE" ]; then
  EXISTING_PROMOTED=$(python3 -c "
import sys, re

content = sys.stdin.read()
m = re.search(r'## Promoted Rules\s*\n(.*?)(?=\n## |\Z)', content, re.DOTALL)
if m:
    print(m.group(1).strip())
else:
    print('')
" < "$VOICE_DRIFT_FILE")
fi

python3 << PYEOF > "$VOICE_DRIFT_FILE"
import re

analysis = """$ANALYSIS_OUTPUT"""
anti_patterns = """$ANTI_PATTERN_OUTPUT"""
match_count = $MATCH_COUNT
rejected_count = $REJECTED_COUNT
today = "$TODAY"

lines = analysis.split('\n') if analysis.strip() else []

output = []
output.append("# Voice Drift Analysis")
output.append(f"")
output.append(f"*Last updated: {today} | Pairs analyzed: {match_count} | Rejected drafts analyzed: {rejected_count}*")
output.append(f"")
output.append(f"> Auto-generated by voice-diff-analysis.sh. Patterns here feed into")
output.append(f"> the morning pipeline produce/revise prompts. Do not edit Observed")
output.append(f"> Patterns — they regenerate weekly. Promote manually or wait for auto-promotion.")
output.append(f"")

# --- Observed Patterns (raw analysis output) ---
output.append("## Observed Patterns")
output.append("")
if analysis.strip():
    output.append(analysis)
else:
    output.append("*Not enough draft-to-published pairs yet (need 3+).*")
output.append("")

# --- Candidate Rules (3+ frequency) ---
output.append("## Candidate Rules")
output.append("")
output.append("*Patterns observed in 3+ diffs. Review and promote to Promoted Rules when confident.*")
output.append("")

freq_pattern = re.compile(r'(\d+)\s*(?:/|out of)\s*(\d+)')
current_section = ""
candidate_entries = []
promoted_entries = []

for line in lines:
    if line.startswith('**') or line.startswith('### ') or line.startswith('## '):
        current_section = line.strip('*# ')
    freq_match = freq_pattern.search(line)
    if freq_match:
        count = int(freq_match.group(1))
        total = int(freq_match.group(2))
        if count >= 5:
            promoted_entries.append(f"- [{current_section}] {line.strip()} *(auto-flagged for promotion)*")
        elif count >= 3:
            candidate_entries.append(f"- [{current_section}] {line.strip()}")

if candidate_entries:
    output.extend(candidate_entries)
else:
    output.append("*No patterns have reached 3+ frequency yet.*")

output.append("")

# --- Promoted Rules (5+ frequency, or manually promoted) ---
output.append("## Promoted Rules")
output.append("")
output.append("*Patterns observed in 5+ diffs. Ready to add to editorial-lessons.md.*")
output.append("")

existing = """${EXISTING_PROMOTED}"""
if existing.strip():
    output.append("### Previously Promoted")
    output.append(existing.strip())
    output.append("")

if promoted_entries:
    output.append("### Newly Promoted ({today})".format(today=today))
    output.extend(promoted_entries)
else:
    if not existing.strip():
        output.append("*No patterns have reached 5+ frequency yet.*")

output.append("")

# --- Anti-Patterns (from rejected drafts) ---
output.append("## Anti-Patterns (from rejected drafts)")
output.append("")
if anti_patterns.strip():
    output.append(f"*{rejected_count} rejected draft(s) analyzed. These are NEVER rules — things the pipeline should avoid.*")
    output.append("")
    output.append(anti_patterns)
else:
    output.append("*No rejected drafts to analyze yet. Use /gcd:reject to mark bad drafts.*")
output.append("")

print('\n'.join(output))
PYEOF

log "Voice drift file written to: $VOICE_DRIFT_FILE ($(wc -c < "$VOICE_DRIFT_FILE" | tr -d ' ') bytes)"

log "=== Voice Diff Analysis Complete ==="
log "Pairs analyzed: $MATCH_COUNT | Rejected drafts analyzed: $REJECTED_COUNT"
