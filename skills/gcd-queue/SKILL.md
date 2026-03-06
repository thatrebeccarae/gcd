---
name: gcd-queue
description: Read-only view of the signal brief queue. Shows unassigned briefs sorted by composite alignment score with pillar match suggestions. Shows already-assigned briefs for the current sprint. Never modifies files. Use when the user runs /gcd:queue.
tools: Read, Glob
---

# GCD Queue

Read-only brief queue viewer. Scans signal brief frontmatter and displays unassigned briefs sorted by impact score with lightweight pillar-fit suggestions, plus a separate view of briefs already assigned to sprints.

## How to Use

```
/gcd:queue    # Show the signal brief queue with pillar fit suggestions
```

## Important Constraints

**This skill is READ-ONLY. It NEVER writes, modifies, or creates any files.**

All pillar data comes from `pillars.json`. Pillar names and keywords are never hardcoded in this skill. If pillars.json changes, the output updates automatically.

Pillar matching in this skill is a lightweight heuristic — keyword intersection only. It is NOT the full scoring the sprint-planner agent performs during /gcd:plan-sprint.

## Behavior

### Step 1: Load Pillar Config

Read `~/your-repo/.planning/pillars.json` using the Read tool.

Parse:
- `pillars` array — each entry has `id`, `name`, `day`, `day_index`, `content_types`, `brief_keywords`
- `quality_gate` section — `min_impact_score`, `min_composite_score`, `stale_days`, `prefer_enriched`

If pillars.json is missing, output this error and stop:

```
Error: pillars.json not found at ~/your-repo/.planning/pillars.json
Run Phase 1 plan 01-02 first to create the config file.
```

Do not proceed past Step 1 if pillars.json is missing.

### Step 2: Calculate Current Sprint Identifier

Determine today's date and calculate the ISO week number.

- ISO week format: `YYYY-WNN` (e.g., `2026-W08`)
- Week starts Monday per ISO 8601
- Week number is zero-padded to 2 digits (W08, not W8)
- This identifier is used to categorize briefs but is NOT used to filter — all briefs are shown regardless of age.

ISO week calculation rule: ISO week 1 is the week containing the first Thursday of the year. Today 2026-02-19 → sprint `2026-W08`.

### Step 3: Scan Brief Queue

Glob: `~/your-vault/briefs/*.md`

For each file found:
1. Read the file
2. Parse YAML frontmatter
3. Extract these fields (all optional — use `—` if absent):
   - `topic` — human-readable brief title or subject
   - `route` — content type (essay, linkedin, twitter-thread)
   - `impact_score` — numeric score (higher = more urgent)
   - `status` — lifecycle state (typically `stub` for new briefs)
   - `signal_date` — when the signal was detected (ISO date)
   - `sprint` — sprint identifier if assigned (e.g., `2026-W08`)
   - `piece_id` — sprint-scoped piece ID if assigned
   - `pillar` — pillar name if already assigned
   - `scheduled` — scheduled publish datetime if assigned
4. Compute `age_days` = today's date minus `signal_date` (integer days). If `signal_date` is absent, treat `age_days` as 0.

### Step 4: Categorize and Sort Briefs

**Unassigned briefs:** `status` is `stub` AND `sprint` field is absent or empty.

**In-Sprint briefs:** `sprint` field is present (any value — not filtered to current week only; all assigned briefs are shown).

Sort unassigned briefs by `composite_score` descending (highest alignment first). Tiebreaker: more recent `signal_date` wins. If composite scores are equal and signal dates are equal, fall back to `impact_score` descending. If `impact_score` is absent, treat as 0.

Sort in-sprint briefs by `sprint` ascending, then by `piece_id` ascending.

### Step 5: Composite Signal Scoring (Unassigned Briefs Only)

Calculate composite scores for each unassigned brief using a lightweight version of the sprint-planner agent's formula. This skill does NOT call the agent — it performs inline scoring.

**Published content scan for pillar distribution:**

1. Glob the following paths to find recently published content:
   - `~/your-vault/content/**/*.md`

2. For each file: read frontmatter, extract `created` or `date` field (ISO date format)

3. Filter to files from the last 4 weeks (28 days before today)

4. For each file, infer which pillar it belongs to:
   - Extract `tags` field from frontmatter (array of strings)
   - For each pillar in pillars.json, count how many of the pillar's `brief_keywords` appear in the file's `tags` (case-insensitive match)
   - Pillar with most keyword matches = best fit
   - If no keywords match any pillar, skip the file

5. Calculate pillar distribution:
   - Count: how many files inferred for each pillar
   - Total: sum of all files
   - Expected: total / number of pillars (equal distribution)
   - Underrepresentation factor for each pillar: `max(0, (expected - count) / expected)`
   - Underrepresentation boost: `min(0.3, underrepresentation_factor * 0.3)`
   - Clamp boost to 0.0-0.3 range

6. **Cold start handling:** If no published files exist in the 28-day window, set all pillar boosts to 0.0

**For each unassigned brief, score against each pillar:**

1. **keyword_normalized:** Count how many of the pillar's `brief_keywords` appear in the brief's `topic` (case-insensitive substring match), divided by `len(brief_keywords)`. Range 0.0-1.0.

2. **route_fit:** 1.0 if the brief's `route` is in the pillar's `content_types` array, else 0.0.

3. **pillar_fit:** `clamp(keyword_normalized + underrep_boost, 0.0, 1.0)` where `underrep_boost` is the pillar's boost from the published content scan. **Note:** Do NOT apply sprint penalty in queue scoring — no sprint context exists yet.

4. **composite_score:** `keyword_normalized * 0.5 + pillar_fit * 0.3 + route_fit * 0.2`

**Best pillar selection:**

- Pillar with the highest `composite_score` for this brief
- Tiebreaker: if two pillars have equal composite scores, prefer the pillar whose `content_types` includes the brief's `route`
- If no keywords from any pillar match the topic (all keyword_normalized = 0), show `—` for Best Pillar Fit, and composite_score = route_fit * 0.2 only

**Visual indicators:**

- Score >= 0.6: no indicator
- Score 0.4-0.59: prefix with `⚠ ` (warning — borderline alignment)
- Score < 0.4: prefix with `⚡ ` (weak signal)

This scoring is a lightweight approximation. The sprint-planner agent applies the full algorithm with sprint assignment penalty during `/gcd:plan-sprint`.

### Step 5b: Apply Age Penalty

For each unassigned brief, after computing composite_score:
- If `age_days > stale_days` (from quality_gate config): multiply composite_score by 0.5
- This penalizes stale briefs in the sort order without hiding them from `--all` view

### Step 6: Output to Terminal

**Quality gate filtering:** Split unassigned briefs into two groups:
- **Active Queue:** briefs where ALL of: `impact_score >= min_impact_score`, `composite_score >= min_composite_score` (after age penalty), AND `age_days <= stale_days`
- **Below Threshold:** everything else

If the user passed the `--all` flag, skip filtering and show all briefs in the Active Queue section.

Output the following format. **Do NOT write any files. Terminal output only.**

```
## Brief Queue — Active (N briefs)

Sorted by composite score (highest alignment first). Run /gcd:plan-sprint to assign briefs to a sprint.

| # | Topic | Route | Impact | Best Pillar Fit | Score | Signal Date |
|---|-------|-------|--------|----------------|-------|-------------|
| 1 | [topic] | [route] | [impact_score] | [pillar name or —] | [0.00 or ⚠ 0.00 or ⚡ 0.00] | [signal_date] |
| 2 | [topic] | [route] | [impact_score] | [pillar name or —] | [0.00 or ⚠ 0.00 or ⚡ 0.00] | [signal_date] |

*Score = keyword (50%) + pillar fit (30%) + route fit (20%)*

## Below Threshold (N briefs)

N briefs below quality threshold (run /gcd:queue --all to see)

## In-Sprint Briefs

| Piece ID | Topic | Pillar | Sprint | Scheduled | Status |
|----------|-------|--------|--------|-----------|--------|
| [piece_id or —] | [topic] | [pillar or —] | [sprint] | [date portion of scheduled, or —] | [status or —] |
```

**Score column:** Display composite score to 2 decimal places. Prefix with visual indicator:
- Score >= 0.6: no indicator
- Score 0.4-0.59: `⚠ ` (warning — borderline alignment)
- Score < 0.4: `⚡ ` (weak signal)

**Scheduled column:** Show date portion only, formatted as `Mon DD` (e.g., `Feb 17`). Show `—` if absent.

### Empty States

Apply the appropriate message for each empty condition:

**No brief files exist at all:**
```
No briefs found in queue. Use /seed-idea to capture content signals.
```

**Brief files exist but all are assigned (none unassigned):**
```
All briefs are assigned to sprints. Brief queue is empty.
```
Then show the In-Sprint section normally.

**No briefs have a sprint field (none in-sprint):**
```
No briefs assigned to any sprint yet.
```
Show after the In-Sprint section header.

**Normal empty unassigned with some in-sprint:** Show the Unassigned section with count 0 and the empty-queue message, then show In-Sprint normally.

## Anti-Patterns — Do NOT

- Write any files. This skill is read-only.
- Call the sprint-planner agent. Queue view uses lightweight inline scoring only.
- Apply sprint penalty in queue scoring — no sprint context exists yet.
- Modify brief frontmatter.
- Show all briefs without quality filtering. Filter by quality_gate config from pillars.json. Use `--all` flag to bypass filtering and show everything.
- Hardcode pillar names or keywords. Always read from pillars.json.

## Files

- **pillars.json:** `~/your-repo/.planning/pillars.json`
- **Brief queue:** `~/your-vault/briefs/*.md`
