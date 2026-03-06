#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=sync-public.conf
source "${SCRIPT_DIR}/sync-public.conf"

# ── Helpers ─────────────────────────────────────────────────────────

log()  { echo "[sync] $*"; }
warn() { echo "[sync] WARNING: $*" >&2; }
die()  { echo "[sync] ERROR: $*" >&2; exit 1; }

# ── Validate ────────────────────────────────────────────────────────

[[ -f "${SOURCE_DIR}/README.md" ]] || die "SOURCE_DIR is not a valid GCD repo: ${SOURCE_DIR}"
log "Source: ${SOURCE_DIR}"
log "Target: ${TARGET_DIR}"

# ── Prepare target ──────────────────────────────────────────────────

mkdir -p "${TARGET_DIR}"

# Clean synced content from target (preserve .git, README, etc.)
if [[ -d "${TARGET_DIR}/skills" ]]; then
  log "Cleaning previous sync..."
  for dir in skills agents assets .planning; do
    if [[ -d "${TARGET_DIR}/${dir}" ]]; then
      rm -rf "${TARGET_DIR}/${dir}"
    fi
  done
  for f in .editorconfig .gitignore; do
    rm -f "${TARGET_DIR}/${f}"
  done
fi

# ── Build rsync exclude list ────────────────────────────────────────

RSYNC_EXCLUDES=()
for p in "${EXCLUDE_PATHS[@]+"${EXCLUDE_PATHS[@]}"}"; do
  RSYNC_EXCLUDES+=(--exclude "$p")
done

# ── Copy files ──────────────────────────────────────────────────────

log "Copying files..."
rsync -a --delete-excluded \
  "${RSYNC_EXCLUDES[@]+"${RSYNC_EXCLUDES[@]}"}" \
  --exclude "README.md" \
  "${SOURCE_DIR}/" "${TARGET_DIR}/"

# ── Generate generic pillars.example.json ───────────────────────────

log "Generating pillars.example.json..."
cat > "${TARGET_DIR}/.planning/pillars.example.json" << 'PILLARS_EOF'
{
  "version": "1.0",
  "quality_gate": {
    "min_impact_score": 15,
    "min_composite_score": 0.4,
    "stale_days": 14,
    "prefer_enriched": true
  },
  "sprint_days": ["Monday", "Tuesday", "Wednesday", "Thursday"],
  "posting_window": {
    "earliest": "08:30",
    "latest": "09:30",
    "timezone": "America/New_York"
  },
  "enforcement": {
    "mode": "rolling-window",
    "window_weeks": 4,
    "flag_missing_after_weeks": 2,
    "hard_block": false
  },
  "pillars": [
    {
      "id": "pillar-one",
      "name": "Technical Deep-Dives",
      "day": "Monday",
      "day_index": 1,
      "post_time": "08:30",
      "timezone": "America/New_York",
      "content_types": ["linkedin", "twitter-thread"],
      "description": "Hands-on technical content — tutorials, architecture, tooling",
      "brief_keywords": ["engineering", "architecture", "tooling", "code", "tutorial"]
    },
    {
      "id": "pillar-two",
      "name": "Industry Strategy",
      "day": "Tuesday",
      "day_index": 2,
      "post_time": "08:30",
      "timezone": "America/New_York",
      "content_types": ["linkedin", "twitter-thread"],
      "description": "Industry trends, market analysis, strategic takes",
      "brief_keywords": ["strategy", "market", "trends", "industry", "analysis"]
    },
    {
      "id": "pillar-three",
      "name": "Career & Leadership",
      "day": "Wednesday",
      "day_index": 3,
      "post_time": "08:30",
      "timezone": "America/New_York",
      "content_types": ["linkedin", "twitter-thread"],
      "description": "Career growth, leadership lessons, professional development",
      "brief_keywords": ["career", "leadership", "hiring", "management", "growth"]
    },
    {
      "id": "pillar-four",
      "name": "Long-Form Essays",
      "day": "Thursday",
      "day_index": 4,
      "post_time": "09:00",
      "timezone": "America/New_York",
      "content_types": ["substack", "linkedin", "twitter-thread"],
      "description": "Long-form essays and newsletter content",
      "brief_keywords": ["essay", "analysis", "opinion", "deep-dive"]
    }
  ]
}
PILLARS_EOF

# Remove the real pillars.json from public repo
rm -f "${TARGET_DIR}/.planning/pillars.json"

# ── Apply text replacements ─────────────────────────────────────────

log "Scrubbing personal references..."

# Helper: sed in-place (macOS compatible)
sedi() { sed -i '' "$@"; }

# Scrub vault paths in skill files
find "${TARGET_DIR}/skills" "${TARGET_DIR}/agents" -name '*.md' -exec \
  sed -i '' 's|~/Popoloto/Repos\.nosync/gcd-dev/|~/your-repo/|g' {} +

find "${TARGET_DIR}/skills" "${TARGET_DIR}/agents" -name '*.md' -exec \
  sed -i '' 's|~/Popoloto/Repos\.nosync/gcd/|~/your-repo/|g' {} +

find "${TARGET_DIR}/skills" "${TARGET_DIR}/agents" -name '*.md' -exec \
  sed -i '' 's|~/Popoloto/03-Areas/professional-content/content/|~/your-vault/content/|g' {} +

find "${TARGET_DIR}/skills" "${TARGET_DIR}/agents" -name '*.md' -exec \
  sed -i '' 's|~/Popoloto/01-Inbox/content-signals/briefs/|~/your-vault/briefs/|g' {} +

find "${TARGET_DIR}/skills" "${TARGET_DIR}/agents" -name '*.md' -exec \
  sed -i '' 's|~/Popoloto/01-Inbox/content-signals/|~/your-vault/signals/|g' {} +

find "${TARGET_DIR}/skills" "${TARGET_DIR}/agents" -name '*.md' -exec \
  sed -i '' 's|~/Popoloto/|~/your-vault/|g' {} +

# Scrub author references
find "${TARGET_DIR}/skills" "${TARGET_DIR}/agents" -name '*.md' -exec \
  sed -i '' 's/Rebecca Rae Barton/Your Name/g' {} +

find "${TARGET_DIR}/skills" "${TARGET_DIR}/agents" -name '*.md' -exec \
  sed -i '' 's/Rebecca Barton/Your Name/g' {} +

find "${TARGET_DIR}/skills" "${TARGET_DIR}/agents" -name '*.md' -exec \
  sed -i '' 's/Rebecca/Your Name/g' {} +

# Scrub specific pillar names from skill/agent files (replace with generic references)
# Quoted variants
find "${TARGET_DIR}/skills" "${TARGET_DIR}/agents" -name '*.md' -exec \
  sed -i '' 's/"Building with AI"/"Pillar One"/g' {} +

find "${TARGET_DIR}/skills" "${TARGET_DIR}/agents" -name '*.md' -exec \
  sed -i '' 's/"E-Commerce & Marketing Strategy"/"Pillar Two"/g' {} +

find "${TARGET_DIR}/skills" "${TARGET_DIR}/agents" -name '*.md' -exec \
  sed -i '' 's/"Career & Leadership"/"Pillar Three"/g' {} +

find "${TARGET_DIR}/skills" "${TARGET_DIR}/agents" -name '*.md' -exec \
  sed -i '' 's/"dgtl dept Essays"/"Pillar Four"/g' {} +

# Unquoted variants (in prose, tables, mappings)
find "${TARGET_DIR}/skills" "${TARGET_DIR}/agents" -name '*.md' -exec \
  sed -i '' 's/Building with AI/Pillar One/g' {} +

find "${TARGET_DIR}/skills" "${TARGET_DIR}/agents" -name '*.md' -exec \
  sed -i '' 's/E-Commerce & Marketing Strategy/Pillar Two/g' {} +

find "${TARGET_DIR}/skills" "${TARGET_DIR}/agents" -name '*.md' -exec \
  sed -i '' 's/dgtl dept Essay/Pillar Four/g' {} +

find "${TARGET_DIR}/skills" "${TARGET_DIR}/agents" -name '*.md' -exec \
  sed -i '' 's/dgtl dept/Pillar Four/g' {} +

# Scrub frontmatter spec
if [[ -f "${TARGET_DIR}/.planning/schemas/frontmatter-spec.md" ]]; then
  sedi 's/"Building with AI"/"Pillar One"/g' "${TARGET_DIR}/.planning/schemas/frontmatter-spec.md"
  sedi 's/"E-Commerce & Marketing Strategy"/"Pillar Two"/g' "${TARGET_DIR}/.planning/schemas/frontmatter-spec.md"
  sedi 's/"Career & Leadership"/"Pillar Three"/g' "${TARGET_DIR}/.planning/schemas/frontmatter-spec.md"
  sedi 's/"dgtl dept Essays"/"Pillar Four"/g' "${TARGET_DIR}/.planning/schemas/frontmatter-spec.md"
  sedi 's/Rebecca Barton/Your Name/g' "${TARGET_DIR}/.planning/schemas/frontmatter-spec.md"
  sedi 's|Popoloto|your-vault|g' "${TARGET_DIR}/.planning/schemas/frontmatter-spec.md"
fi

# ── Verify: check for personal data leaks ───────────────────────────

log "Checking for personal data leaks..."
LEAKS=0
for pattern in "Rebecca" "Popoloto" "gcd-dev" "dgtl dept"; do
  MATCHES=$(grep -r --include='*.md' --include='*.json' "$pattern" \
    "${TARGET_DIR}/skills" "${TARGET_DIR}/agents" "${TARGET_DIR}/.planning" 2>/dev/null || true)
  if [[ -n "$MATCHES" ]]; then
    echo "  LEAK: '$pattern' found:"
    echo "$MATCHES" | head -5
    LEAKS=$((LEAKS + 1))
  fi
done

if [[ "$LEAKS" -gt 0 ]]; then
  die "$LEAKS personal data pattern(s) found in public repo — aborting"
fi
log "Clean — no personal data leaks detected"

# ── Summary ─────────────────────────────────────────────────────────

SKILL_COUNT=$(find "${TARGET_DIR}/skills" -name 'SKILL.md' | wc -l | tr -d ' ')
AGENT_COUNT=$(find "${TARGET_DIR}/agents" -name '*.md' | wc -l | tr -d ' ')
log "Done. ${SKILL_COUNT} skills + ${AGENT_COUNT} agents synced to ${TARGET_DIR}"
