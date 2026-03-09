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
  --exclude "/README.md" \
  "${SOURCE_DIR}/" "${TARGET_DIR}/"

# ── Generate generic pillars.example.json ───────────────────────────

log "Generating pillars.example.json..."
cat > "${TARGET_DIR}/.planning/pillars.example.json" << 'PILLARS_EOF'
{
  "version": "1.0",
  "quality_gate": {
    "min_impact_score": 10,
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
      "name": "Product Launches",
      "day": "Monday",
      "day_index": 1,
      "post_time": "08:30",
      "timezone": "America/New_York",
      "content_types": ["linkedin", "twitter-thread"],
      "description": "New product announcements, feature spotlights, launch stories",
      "brief_keywords": ["launch", "product", "feature", "release", "announcement"]
    },
    {
      "id": "pillar-two",
      "name": "Founder Stories",
      "day": "Tuesday",
      "day_index": 2,
      "post_time": "08:30",
      "timezone": "America/New_York",
      "content_types": ["linkedin", "twitter-thread"],
      "description": "Founder journey, lessons learned, behind-the-scenes",
      "brief_keywords": ["founder", "startup", "lessons", "journey", "story"]
    },
    {
      "id": "pillar-three",
      "name": "Engineering Culture",
      "day": "Wednesday",
      "day_index": 3,
      "post_time": "08:30",
      "timezone": "America/New_York",
      "content_types": ["linkedin", "twitter-thread"],
      "description": "Team practices, hiring philosophy, engineering values",
      "brief_keywords": ["engineering", "culture", "hiring", "team", "practices"]
    },
    {
      "id": "pillar-four",
      "name": "Weekly Roundup",
      "day": "Thursday",
      "day_index": 4,
      "post_time": "09:00",
      "timezone": "America/New_York",
      "content_types": ["substack", "linkedin", "twitter-thread"],
      "description": "Curated weekly digest and newsletter content",
      "brief_keywords": ["roundup", "digest", "newsletter", "weekly", "curated"]
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

# Scrub vault paths in skill and pipeline files
find "${TARGET_DIR}/skills" "${TARGET_DIR}/agents" -name '*.md' -exec \
  sed -i '' 's|~/Popoloto/Repos\.nosync/gcd-dev/|~/your-repo/|g' {} +

find "${TARGET_DIR}/skills" "${TARGET_DIR}/agents" -name '*.md' -exec \
  sed -i '' 's|~/Popoloto/Repos\.nosync/get-content-done/|~/your-repo/|g' {} +

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

find "${TARGET_DIR}/skills" "${TARGET_DIR}/agents" -name '*.md' -exec \
  sed -i '' 's/dgtl-dept/pillar-four/g' {} +

# Scrub pipeline scripts and workflow
if [[ -d "${TARGET_DIR}/pipeline" ]]; then
  # TARS-specific paths → generic
  find "${TARGET_DIR}/pipeline" \( -name '*.sh' -o -name '*.md' \) -exec \
    sed -i '' 's|/Users/tars/|~/|g' {} +
  find "${TARGET_DIR}/pipeline" \( -name '*.sh' -o -name '*.md' \) -exec \
    sed -i '' 's|tars@tars\.local|user@your-server|g' {} +
  find "${TARGET_DIR}/pipeline" \( -name '*.sh' -o -name '*.md' \) -exec \
    sed -i '' 's|TARS (Mac Mini M4 Pro)|your macOS host|g' {} +
  find "${TARGET_DIR}/pipeline" \( -name '*.sh' -o -name '*.md' \) -exec \
    sed -i '' 's|TARS|your host|g' {} +
  find "${TARGET_DIR}/pipeline" \( -name '*.sh' -o -name '*.md' \) -exec \
    sed -i '' 's|tars\.local|your-server|g' {} +
  find "${TARGET_DIR}/pipeline" \( -name '*.sh' -o -name '*.md' \) -exec \
    sed -i '' 's|com\.tars\.|com.gcd.|g' {} +

  # Author references in shell scripts
  find "${TARGET_DIR}/pipeline" -name '*.sh' -exec \
    sed -i '' 's/Rebecca Barton/Your Name/g' {} +
  find "${TARGET_DIR}/pipeline" -name '*.sh' -exec \
    sed -i '' 's/Rebecca/Your Name/g' {} +

  # Vault paths in shell scripts
  find "${TARGET_DIR}/pipeline" -name '*.sh' -exec \
    sed -i '' 's|~/Popoloto|~/your-vault|g' {} +
  find "${TARGET_DIR}/pipeline" -name '*.sh' -exec \
    sed -i '' 's|Popoloto|your-vault|g' {} +

  # Vault paths and pillar names in README
  if [[ -f "${TARGET_DIR}/pipeline/README.md" ]]; then
    sedi 's|~/Popoloto/[^ ]*|~/your-vault/...|g' "${TARGET_DIR}/pipeline/README.md"
    sedi 's|Popoloto|your-vault|g' "${TARGET_DIR}/pipeline/README.md"
    sedi 's|dgtl dept Essays|Pillar Four|g' "${TARGET_DIR}/pipeline/README.md"
    sedi 's|dgtl dept|Pillar Four|g' "${TARGET_DIR}/pipeline/README.md"
  fi

  # Scrub workflow.json: author refs and vault paths in JS code strings
  if [[ -f "${TARGET_DIR}/pipeline/workflow.json" ]]; then
    sedi "s/Rebecca Barton's/Your Name's/g" "${TARGET_DIR}/pipeline/workflow.json"
    sedi "s/Rebecca's/Your Name's/g" "${TARGET_DIR}/pipeline/workflow.json"
    sedi "s/REBECCA'S/YOUR NAME'S/g" "${TARGET_DIR}/pipeline/workflow.json"
    sedi 's/REBECCA/YOUR NAME/g' "${TARGET_DIR}/pipeline/workflow.json"
    sedi 's/Rebecca/Your Name/g' "${TARGET_DIR}/pipeline/workflow.json"
    sedi 's|[Pp]opoloto|your-vault|g' "${TARGET_DIR}/pipeline/workflow.json"
    sedi 's|/Users/tars/|~/|g' "${TARGET_DIR}/pipeline/workflow.json"
    sedi 's|dgtl-dept|pillar-four|g' "${TARGET_DIR}/pipeline/workflow.json"
    sedi 's|dgtl dept|Pillar Four|g' "${TARGET_DIR}/pipeline/workflow.json"
    sedi 's|Building with AI|Pillar One|g' "${TARGET_DIR}/pipeline/workflow.json"
    sedi 's|E-Commerce & Marketing Strategy|Pillar Two|g' "${TARGET_DIR}/pipeline/workflow.json"
    sedi 's|Career & Leadership|Pillar Three|g' "${TARGET_DIR}/pipeline/workflow.json"
  fi
fi

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
for pattern in "Rebecca" "Popoloto" "gcd-dev" "dgtl dept" "/Users/tars" "tars.local"; do
  MATCHES=$(grep -r --include='*.md' --include='*.json' --include='*.sh' "$pattern" \
    "${TARGET_DIR}/skills" "${TARGET_DIR}/agents" "${TARGET_DIR}/.planning" "${TARGET_DIR}/pipeline" 2>/dev/null || true)
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
