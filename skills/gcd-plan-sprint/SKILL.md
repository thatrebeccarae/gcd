---
name: gcd-plan-sprint
description: Interactive sprint planning session. Reads the brief queue, calls gcd-sprint-planner agent for recommendations, lets user select and assign briefs to sprint slots, and writes sprint fields to brief frontmatter. Ends by showing /gcd:status output. Use when the user runs /gcd:plan-sprint.
tools: Read, Write, Glob
---

# GCD Plan Sprint

Interactive sprint planning orchestrator. Walks through reading the brief queue, calling the gcd-sprint-planner agent for scored recommendations, presenting suggestions for user confirmation, and writing sprint fields to confirmed brief files.

## How to Use

```
/gcd:plan-sprint    # Start an interactive sprint planning session
```

## Important Constraints

**This skill writes ONLY to brief files after explicit user confirmation.** Nothing is written without consent.

- Do NOT write SPRINT.md — that is /gcd:status domain exclusively.
- Do NOT change the `status` field on any brief — status stays `stub` until Phase 3.
- Do NOT create content files — Phase 2 writes brief frontmatter only.
- Do NOT auto-assign without user confirmation — every assignment requires explicit consent.
- Do NOT call /gcd:status directly — invite the user to run it themselves.
- Do NOT block on unfilled pillar slots — 1-4 assigned pieces is a valid sprint.

---

## Behavior

Execute each step in order. Do not skip steps.

### Step 1: Load Pillar Config

Read `~/your-repo/.planning/pillars.json` using the Read tool.

Parse and extract:
- `pillars` array — each entry has `id`, `name`, `day`, `day_index`, `post_time`, `timezone`, `content_types`, `brief_keywords`
- `quality_gate` section — `min_impact_score`, `min_composite_score`, `stale_days`, `prefer_enriched`
- `posting_window` — `earliest`, `latest`, `timezone`
- `enforcement` — `window_weeks`, `hard_block`

If pillars.json is missing, output this error and STOP:

```
Error: pillars.json not found at ~/your-repo/.planning/pillars.json
Run Phase 1 plan 01-02 first to create the config file.
```

### Step 2: Determine Sprint Identifier

Ask the user:

```
Planning sprint for this week (YYYY-WNN) or a specific week? [Enter for current week]
```

**Default:** The current ISO week identifier.

- ISO week format: `YYYY-WNN` (e.g., `2026-W08`)
- Week starts Monday per ISO 8601
- Week number is zero-padded to 2 digits (W08, not W8)
- ISO week 1 is the week containing the first Thursday of the year

**Calculate the Monday date** for the target sprint week. This is required for:
- Piece ID computation (week number)
- Scheduled datetime computation (add days from Monday)
- Staleness detection (passed to sprint-planner agent)

Example: Sprint `2026-W08` → Monday is 2026-02-23.

### Step 3: Scan the Brief Queue

Glob: `~/your-vault/briefs/*.md`

For each file, read the full content and parse YAML frontmatter. Extract:
- `topic`, `route`, `impact_score`, `status`, `signal_date`
- `sprint`, `piece_id`, `pillar`, `scheduled`

**Filter to unassigned briefs:** files where `sprint` field is absent or empty.

**Quality gate pre-filtering:** Load `quality_gate` from pillars.json (parsed in Step 1). Before passing briefs to the sprint-planner agent:
- Exclude briefs where `impact_score < min_impact_score` (treat absent impact_score as 0)
- Note stale briefs (`signal_date` > `stale_days` before sprint Monday) separately — still pass to agent but flagged as stale
- Report: `Filtered N low-quality briefs from queue. Passing M briefs to sprint-planner.`
- If no briefs remain after filtering, treat as empty queue (see below)

**Empty queue handling:** If no unassigned briefs exist (or none pass quality gate), output and STOP:

```
No unassigned briefs in queue. Use /seed-idea to capture signals first.
```

**Already-assigned to this sprint:** Before proceeding, identify any briefs already assigned to this specific sprint week. Report them:

```
Already assigned to [sprint identifier]: [topic list]
```

This prevents double-assignment.

### Step 4: Call GCD Sprint-Planner Agent

Invoke the gcd-sprint-planner agent at `~/.claude/agents/gcd-sprint-planner.md`.

Pass as context:
- The full content of all unassigned brief files
- The sprint identifier from Step 2
- The Monday date of the sprint week

The gcd-sprint-planner agent will:
- Read pillars.json and retros itself via its own Read tool
- Load most recent performance summary from .planning/retros/*-performance.md
- Score each brief against all pillars using composite scoring: keyword (50%) + pillar fit (30%) + route fit (20%)
- Apply performance boost to pillar_fit for high-performing route+pillar combos (+0.1) and low-performing combos (-0.05)
- Scan published content from last 4 weeks for pillar underrepresentation detection
- Calculate composite scores (0.0-1.0) with underrepresentation boost, performance boost, and sprint assignment penalty
- Calculate strategy drift deviation (actual vs target pillar distribution)
- Suggest best-fit pillar assignments
- Check rolling-window pillar coverage
- Flag staleness for briefs older than 14 days before sprint Monday

The agent returns seven sections:
1. Strategy Drift Warning (drift detection with deviation table — always present)
2. Performance Insights (route performance, patterns, scoring impact — always present)
3. Brief Analysis table (with full score breakdown: Keyword, Pillar Fit, Route Fit, composite Score)
4. Suggested Sprint Manifest (all 4 slots, EMPTY if no brief fits)
5. Gap Warnings
6. Pillar Coverage (Rolling 4-Week Window)
7. Staleness Notes

### Step 5: Present Recommendations to User

Display the agent's full output. The Strategy Drift Warning section appears first, followed by Performance Insights — if patterns are detected, the user sees what's working and what isn't BEFORE reviewing brief assignments.

Then ask:

```
## Sprint-Planner Recommendations

[agent output displayed here]

---
Accept all suggestions / Modify individual slots / Cancel?
[accept / modify / cancel]
```

Ensure all seven agent sections are visible before asking for a response. Do not truncate agent output.

Ensure the Brief Analysis table is displayed with all columns including score breakdown (Keyword, Pillar Fit, Route Fit, Score) and the formula legend below it. Do not truncate or hide score columns.

### Step 6: Handle User Response

#### If Accept All

Proceed directly to Step 7 using the agent's suggested assignments as-is.

Only process briefs the agent assigned to a pillar (slots marked EMPTY are left unassigned — this is valid).

#### If Modify

Walk through each pillar slot one at a time (Monday through Thursday, by `day_index`):

```
Slot [N]: [Pillar Name] ([Day])
Agent suggests: [topic slug or "no suggestion (EMPTY)"]

Accept? [Y/n/skip/pick]
  Y or Enter  — accept the agent's suggestion for this slot
  n           — leave this slot unfilled this sprint
  skip        — same as n
  pick        — show all unassigned briefs, user selects one
```

**If user selects "pick":**
- Show the list of all unassigned briefs with their topic, route, and impact_score
- Ask: "Enter brief number to assign to this slot, or 0 to skip:"
- If user enters a number, assign that brief to this slot
- If user enters 0, leave this slot unfilled

After all 4 slots, show the final manifest:

```
## Proposed Sprint Plan — [sprint identifier]

| Slot | Pillar | Day | Brief | piece_id |
|------|--------|-----|-------|----------|
| 1 | [Pillar Name] | Monday    | [topic or EMPTY] | [W08-01 or —] |
| 2 | [Pillar Name] | Tuesday   | [topic or EMPTY] | [W08-02 or —] |
| 3 | [Pillar Name] | Wednesday | [topic or EMPTY] | [W08-03 or —] |
| 4 | [Pillar Name] | Thursday  | [topic or EMPTY] | [W08-04 or —] |

Confirm this sprint plan? [Y/n]
```

- If confirmed (Y or Enter): proceed to Step 7
- If not confirmed (n): offer to re-modify or cancel:
  ```
  Re-modify slots or cancel? [modify / cancel]
  ```

#### If Cancel

Output and STOP — no files are written:

```
Sprint planning cancelled. No changes made.
```

### Step 7: Compute Scheduled Datetimes

For each confirmed assignment (slots that have a brief assigned, not EMPTY):

**Fields to compute:**

**`sprint`:** The sprint identifier from Step 2 (e.g., `2026-W08`).

**`piece_id`:** Format:
```
"W" + zero_pad(iso_week_number, 2) + "-" + zero_pad(pillar.day_index, 2)
```
Examples:
- Sprint `2026-W08`, pillar `day_index=1` → `W08-01`
- Sprint `2026-W08`, pillar `day_index=4` → `W08-04`

**`pillar`:** The pillar `name` string exactly as it appears in pillars.json (e.g., `"Pillar One"`, `"Pillar Two"`, `"Pillar Three"`, `"Pillar Four"`).

**`scheduled`:** Compute as follows:
1. Start with the sprint week's Monday date (calculated in Step 2)
2. Add `(pillar.day_index - 1)` days to get the correct weekday:
   - day_index 1 (Monday) → +0 days
   - day_index 2 (Tuesday) → +1 day
   - day_index 3 (Wednesday) → +2 days
   - day_index 4 (Thursday) → +3 days
3. Set time to `pillar.post_time` (from pillars.json, e.g., `"08:30"` or `"09:00"`)
4. Set timezone to `pillar.timezone` (from pillars.json, e.g., `"America/New_York"`)
5. Determine UTC offset:
   - US Eastern DST (EDT, UTC-4): second Sunday of March through first Sunday of November
   - US Eastern Standard (EST, UTC-5): all other dates
6. Format as ISO 8601: `YYYY-MM-DDThh:mm:ss±HH:MM`
   - Example EST: `2026-02-23T08:30:00-05:00`
   - Example EDT: `2026-05-04T08:30:00-04:00`

### Step 8: Write Frontmatter to Brief Files

For each confirmed assignment:

1. Read the brief file's full content using the Read tool.
2. Locate the YAML frontmatter block (between `---` delimiters at the top of the file).
3. Add or update exactly these 4 fields in the frontmatter:
   ```yaml
   sprint: "2026-W08"
   piece_id: "W08-01"
   pillar: "Pillar One"
   scheduled: "2026-02-23T08:30:00-05:00"
   ```
4. Preserve ALL existing frontmatter fields without modification:
   - `topic`, `route`, `impact_score`, `status`, `signal_date` — unchanged
   - Any other fields present — unchanged
5. Do NOT change the `status` field under any circumstances. It stays `stub`.
6. Write the updated file back using the Write tool.

**Frontmatter preservation rule:** If a field already exists, update its value in place. If it does not exist, append it to the frontmatter block. Never remove existing fields.

### Step 9: Confirm and Invite Verification

After all writes complete, output a confirmation summary:

```
Sprint [YYYY-WNN] planned: N/4 pillar slots filled.

| Piece ID | Pillar | Brief | Scheduled |
|----------|--------|-------|-----------|
| W08-01 | Pillar One | [topic] | Mon Feb 23, 8:30 AM ET |
| W08-02 | Pillar Two | [topic] | Tue Feb 24, 8:30 AM ET |
```

If any pillar slots were left unfilled, note them:

```
Unfilled slots: [pillar name(s)] — no brief assigned this sprint.
```

Then close with:

```
Run `/gcd:status` to see your full sprint manifest.
```

Do NOT call /gcd:status yourself. Do NOT generate a SPRINT.md file. The user runs the verification command.

---

## Files

- **pillars.json:** `~/your-repo/.planning/pillars.json`
- **Brief queue:** `~/your-vault/briefs/*.md`
- **Sprint-planner agent:** `~/.claude/agents/gcd-sprint-planner.md`

**Content directory:**
- `~/your-vault/content/` — all content (approved = frontmatter `status: approved`, not a directory)
- `~/your-repo/.planning/retros/` — retro records and performance summaries

## Anti-Patterns — Do NOT

- Write SPRINT.md. That is /gcd:status domain exclusively.
- Change `status` to `draft`, `planned`, or anything else. Status stays `stub` until Phase 3.
- Create content files. Phase 2 writes brief frontmatter only.
- Auto-assign without user confirmation. Every assignment requires explicit consent.
- Block on unfilled pillar slots. 1-4 assigned pieces is a valid sprint.
- Call /gcd:status directly. Invite the user to run it themselves.
- Score briefs inline. All scoring is delegated to the sprint-planner agent.
- Hardcode pillar names or keywords. Always read from pillars.json.
- Write to any file before Step 8 (user confirmation must occur first in Step 6).
