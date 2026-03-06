---
name: gcd-status
description: Show current sprint state and pipeline overview. Read-only — never modifies files. Use when the user runs /gcd:status.
license: MIT
origin: custom
author: Your Name
author_url: https://github.com/thatrebeccarae
tools: Read, Glob
---

# GCD Status

Read-only sprint and pipeline overview. Scans content file frontmatter and displays the current sprint state — pieces, pillars, publish slots, and per-piece lifecycle status.

## How to Use

```
/gcd:status    # Show current sprint state and pipeline overview
```

## Important Constraints

**This skill is READ-ONLY. It NEVER writes, modifies, or creates any files.**

All pillar data comes from `pillars.json`. Pillar names, schedule days, and posting times are never hardcoded in this skill. If pillars.json changes, the output updates automatically.

Files without GCD frontmatter fields are silently excluded. No errors, no warnings for missing fields.

## Behavior

### Step 1: Load Config

Read `~/your-repo/.planning/pillars.json`.

Parse:
- `pillars` array — each entry has `id`, `name`, `day`, `post_time`, `timezone`, `content_types`
- `enforcement` block — `mode`, `window_weeks`, `hard_block`
- `posting_window` — `earliest`, `latest`, `timezone`

If pillars.json is missing, output this error and stop:

```
Error: pillars.json not found at ~/your-repo/.planning/pillars.json
Run Phase 1 plan 01-02 first to create the config file.
```

Do not proceed past Step 1 if pillars.json is missing.

### Step 2: Determine Current Sprint

Calculate the current ISO week from today's date.

- ISO week format: `YYYY-WNN` (e.g., `2026-W08`)
- Week starts Monday per ISO 8601
- Week number is zero-padded to 2 digits (W08, not W8)

Display:
- Sprint identifier: `YYYY-WNN`
- Week date range: `Mon DD Mon – Sun DD Mon, YYYY` (e.g., `Mon 16 Feb – Sun 22 Feb, 2026`)

### Step 3: Scan Content Files

Glob these directories for `.md` files:

```
~/your-vault/content/**/*.md
```

For each file found:
1. Read the file
2. Parse YAML frontmatter
3. Check if `sprint` field is present
4. If `sprint` field matches the current sprint identifier (e.g., `"2026-W08"`): include the file
5. If `sprint` field is absent OR does not match current sprint: skip silently — no error, no warning

For included files, extract these fields (all optional — use `—` if absent):
- `piece_id` — sprint-scoped ID (e.g., `"W08-01"`)
- `pillar` — must match a pillar `name` from pillars.json
- `platform` or `type` — to determine content type (linkedin, substack, etc.)
- `brief_slug` — links back to originating brief
- `status` — lifecycle state (stub, draft, reviewed, approved, published, measured)
- `scheduled` — ISO datetime with timezone (e.g., `"2026-02-17T08:30:00-05:00"`)
- File path — for display in Pieces table

### Step 4: Scan Brief Queue

Glob: `~/your-vault/briefs/*.md`

Load `quality_gate` from pillars.json (parsed in Step 1):
- `min_impact_score` — minimum impact score to show in queue
- `stale_days` — briefs older than this are excluded

For each file:
1. Read the file
2. Parse YAML frontmatter
3. Classify into one of two groups:

**In-sprint briefs:** Include if `sprint` field matches current sprint identifier.

**Unassigned queue:** Include if `status` is `"stub"` AND no `sprint` field is present. These are briefs waiting to be assigned to a sprint.

Extract from each brief (all optional — use `—` if absent):
- `topic` — brief slug/identifier
- `pillar` — pillar name
- `route` — content type (essay, linkedin, twitter-thread)
- `impact_score` — numeric score
- `signal_date` — when the signal was detected (ISO date)
- `status` — should be `stub` for unassigned queue
- `sprint` — present only for in-sprint briefs

**Quality gate filtering for unassigned briefs:**
- Compute `age_days` = today minus `signal_date` (integer days)
- Exclude briefs where `impact_score < min_impact_score` (treat absent impact_score as 0)
- Exclude briefs where `age_days > stale_days`
- Track the count of excluded briefs as `hidden_count`

If no brief files exist, show empty queue section — not an error.

### Step 5: Assemble Pillar Coverage

For each pillar loaded from pillars.json (in order as they appear in the array):
1. Check if any sprint piece (from Step 3) has `pillar` matching this pillar's `name`
2. If match found: note the piece_id and status
3. If no match: show `—` for Piece ID and Status

Build the Pillar Coverage table:

| Pillar | Day | Slot | Piece ID | Status |
|--------|-----|------|----------|--------|
| [pillar.name] | [pillar.day abbreviated to 3 chars] | [pillar.post_time with AM/PM ET] | [piece_id or —] | [status or —] |

Format the Slot as: `8:30 AM ET` or `9:00 AM ET` (remove leading zero from hour, append "AM ET").

Calculate coverage count: `N/4 pillars assigned` where N is the count of pillars with a matched piece.

**Note on multiple pieces per pillar:** If more than one sprint piece maps to the same pillar, show the piece with the earliest `scheduled` date in the coverage table. All pieces are shown in the Pieces table (Step 6).

### Step 6: Assemble Pieces Table

Combine sprint content files (Step 3) and in-sprint briefs (Step 4) into a single pieces list.

For each piece build a row:

| ID | Pillar | Type | Brief | File | Status | Scheduled |
|----|--------|------|-------|------|--------|-----------|

Field mapping:
- **ID**: `piece_id` value, or `—` if absent
- **Pillar**: `pillar` value, or `—` if absent
- **Type**: Derive from `platform` field (linkedin → `linkedin`, substack → `essay`, twitter → `twitter`). For brief files, use `route` field. Show `—` if neither present.
- **Brief**: `brief_slug` value (link to originating brief), or `—` if absent
- **File**: Vault-relative path of the file (strip `~/your-vault/` prefix for readability). Show `briefs/[filename]` for brief-only entries.
- **Status**: `status` value, or `—` if absent
- **Scheduled**: Date portion of `scheduled` field formatted as `Mon DD` (e.g., `Feb 17`). Show `—` if absent.

Sort order: Pieces with `scheduled` dates first (ascending), then pieces without `scheduled` dates (alphabetical by piece_id).

If no pieces in sprint: show one row of `— | — | — | — | — | — | —` with a note "(empty sprint)"

### Step 7: Pipeline Health

Count all sprint pieces (content files + in-sprint briefs combined) by their `status` field value.

Count each of the 6 lifecycle states:
- `stub` — brief captured, not yet drafting
- `draft` — in-progress drafting
- `reviewed` — editor-in-chief Gate 1 passed
- `approved` — human approved, publish-ready
- `published` — live on platform
- `measured` — metrics captured, terminal state

Display as a single inline line:

```
stub: N  |  draft: N  |  reviewed: N  |  approved: N  |  published: N  |  measured: N
```

Where N is the count (0 for any state with no pieces).

### Step 8: Display Output

Output the complete sprint summary to the terminal. Use the following format (based on SPRINT.md template):

```
<!-- Sprint view generated by /gcd:status — read-only, do not edit -->
# Sprint: [YYYY-WNN]

**Week:** [Mon DD Mon – Sun DD Mon, YYYY]
**Generated:** [YYYY-MM-DDTHH:MM:SS-05:00]

---

## Pillar Coverage

| Pillar | Day | Slot | Piece ID | Status |
|--------|-----|------|----------|--------|
[one row per pillar from pillars.json]

**Coverage:** N/4 pillars assigned

---

## Pieces

| ID | Pillar | Type | Brief | File | Status | Scheduled |
|----|--------|------|-------|------|--------|-----------|
[one row per sprint piece]

---

## Pipeline Health

\```
stub: N  |  draft: N  |  reviewed: N  |  approved: N  |  published: N  |  measured: N
\```

---

## Brief Queue (Unassigned)

[List of quality-filtered unassigned stubs with topic and pillar, or "(no unassigned briefs)" if empty]
[If hidden_count > 0: "(N low-signal briefs hidden)"]

---

## Strategy Drift (4-week rolling window)

| Pillar | Target | Actual | Count | Deviation |
|--------|--------|--------|-------|-----------|
| [pillar.name] | [target]% | [actual]% | [count] | [status indicator] |

**Total pieces (last 4 weeks):** [total]
**Rolling window:** [four_weeks_ago] to [today]

---

## Sprint Velocity (last 3 sprints)

| Sprint | Planned | Published | Velocity |
|--------|---------|-----------|----------|
| [sprint] | [planned] | [published] | [velocity]% |

**3-sprint trend:** [↗ improving / → stable / ↘ declining]

---

## Pipeline Bottlenecks (current sprint)

| Status | Count |
|--------|-------|
| [status] | [count] |

**Avg creation-to-publish:** [N.N days] (based on [M] published pieces)

---
```

**CRITICAL: Do NOT write this output to any file. Output to terminal only.**

The SPRINT.md file at `~/your-repo/.planning/SPRINT.md` is a template only — do not write to it.

### Step 9: Invoke gcd-strategy-auditor Agent

Delegate strategy health analysis to the `gcd-strategy-auditor` agent. This replaces inline computation of drift, velocity, and bottleneck data.

**Calculate sprint Monday date** from the current sprint identifier (Step 2):
- ISO week YYYY-WNN → Monday is the first day of that week

**Invoke gcd-strategy-auditor** via Task tool:

```
Task(
  prompt="Analyze strategy health for the GCD content pipeline.

Current sprint: [YYYY-WNN]
Sprint Monday date: [YYYY-MM-DD]
Pillars config: ~/your-repo/.planning/pillars.json
Retros path: ~/your-repo/.planning/retros/
Content paths:
  - ~/your-vault/content/**/*.md

Current sprint piece statuses (from Step 3 scan):
[List each piece_id and its status from the sprint scan]

Return your combined strategy_health YAML output.",
  subagent_type="gcd-strategy-auditor",
  model="sonnet",
  description="Strategy health audit"
)
```

**Parse the agent's `strategy_health` response** and map to display template sections:

### Step 9a: Format Strategy Drift Section

From `strategy_health.strategy_drift`:

**If `total_pieces >= 4`:** Populate the Strategy Drift table using `distribution` entries — one row per pillar with Target, Actual, Count, and Deviation columns.

**Status indicator per row:**
- If `status: "drifting"`: show `⚠️ [deviation]`
- If `status: "ok"`: show `✓ within range`

**If `total_pieces < 4`:** Display the agent's `message` field (insufficient data notice).

**Important:** Do NOT add any actionable recommendations in this section. Status is read-only. Drift warnings with recommendations belong only in /gcd:plan-sprint.

### Step 9b: Format Sprint Velocity Section

From `strategy_health.sprint_velocity`:

**If agent returned sprint data:** Populate the Sprint Velocity table from `sprints` array. Show trend from `trend` field using arrows:
- `improving` → `↗ improving`
- `declining` → `↘ declining`
- `stable` → `→ stable`

**If insufficient data:** Display the agent's `message` field.

### Step 9c: Format Pipeline Bottlenecks Section

From `strategy_health.pipeline_bottlenecks`:

Populate the Pipeline Bottlenecks table from `status_counts`. Only show statuses with count > 0. Display `avg_dwell_days` if available. Show the agent's `message` field for bottleneck summary.

**Cold start handling for all three sections:** If the agent returns insufficient data messages, display them as-is. Do not fabricate data or error — graceful degradation is expected.

### Empty Sprint Handling

If Step 3 finds zero pieces for the current sprint:

- Pillar Coverage table: all rows show `—` for Piece ID and Status
- Pieces table: show "(empty sprint — no pieces found for [YYYY-WNN])"
- Pipeline Health: all counts are 0
- Brief Queue: show unassigned stubs if any exist, or "(no briefs in queue)"

Do not error. An empty sprint is a valid state (e.g., first sprint of a new GCD setup).

## Reference Data

### Lifecycle Status Values

| Status | Meaning |
|--------|---------|
| `stub` | Brief captured, not yet in sprint or drafting |
| `draft` | In-progress drafting — piece assigned to sprint |
| `reviewed` | Editor-in-chief Gate 1 passed |
| `approved` | Human approved via /gcd:approve — publish-ready |
| `published` | Live on platform |
| `measured` | Metrics captured — terminal state |

### Content Type Mapping

| `platform` field | Display label |
|-----------------|---------------|
| `linkedin` | linkedin |
| `substack` | essay |
| `twitter` | twitter |

### Sprint Filter Rule

The `sprint` field is the primary filter. A file is in the current sprint if and only if its `sprint` frontmatter field exactly matches the current `YYYY-WNN` identifier. No fuzzy matching. No date-range inference.

### ISO Week Calculation

ISO week 1 is the week containing the first Thursday of the year (or equivalently, the week containing January 4th). Weeks start on Monday.

To calculate the current sprint identifier:
1. Get today's date
2. Calculate ISO week number (1-53)
3. Zero-pad to 2 digits
4. Format: `[YYYY]-W[NN]` (e.g., today is 2026-02-19 → sprint is `2026-W08`)

## Files

- **pillars.json:** `~/your-repo/.planning/pillars.json`
- **Content files:** `~/your-vault/03-Areas/professional-content/`
- **Brief queue:** `~/your-vault/briefs/`
- **SPRINT.md template (do not write):** `~/your-repo/.planning/SPRINT.md`
- **gcd-strategy-auditor agent:** `~/.claude/agents/gcd-strategy-auditor.md`
