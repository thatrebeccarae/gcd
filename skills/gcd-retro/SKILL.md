---
name: gcd-retro
description: Close a sprint with a structured retrospective. Auto-scans pipeline performance from frontmatter, prompts for qualitative notes, handles stalled/incomplete pieces (carry-over or cancel), and writes a retro record to .planning/retros/. Use when the user runs /gcd:retro.
license: MIT
origin: custom
author: Your Name
author_url: https://github.com/thatrebeccarae
tools: Read, Write, Glob, Bash
---

# /gcd:retro — Sprint Close Retrospective

Close a sprint with auto-calculated pipeline metrics, qualitative reflections, and structured handling of incomplete work.

**Purpose:** Closes the GCD loop by giving users a structured sprint close ceremony. Auto-scanned pipeline data (throughput, gate performance, route performance, pillar coverage) replaces manual tracking. Qualitative prompts capture why pieces stalled. The retro record feeds the Phase 2 sprint-planner agent's rolling window for pillar drift detection.

**When to use:** User runs `/gcd:retro` or `/gcd:retro YYYY-WNN` at the end of a sprint week.

**Output:** Retro record written to `.planning/retros/YYYY-WNN.md` with hybrid YAML frontmatter + markdown body.

---

## Step 1: Determine Current Sprint

Calculate the current ISO week from today's date.

- ISO week format: `YYYY-WNN` (e.g., `2026-W08`)
- Week starts Monday per ISO 8601
- Week number is zero-padded to 2 digits

If the user provides a sprint argument (`/gcd:retro 2026-W07`), use that instead.

Check if retro already exists at `.planning/retros/[sprint].md`. If it exists, error: "Retro for [sprint] already exists at .planning/retros/[sprint].md. Edit the file manually to add notes. To add engagement metrics to individual pieces, edit the piece's frontmatter directly (see frontmatter-spec.md for engagement_metrics schema)." Stop.

**Example:**

```bash
# Calculate current ISO week
date +"%G-W%V"  # Returns: 2026-W08
```

**Overwrite protection:** Retro files are one-time records. Never overwrite an existing retro. This check must happen before any other work.

---

## Step 2: Load Config

Read `~/your-repo/.planning/pillars.json`.

Parse:
- `pillars` array — pillar names, day_index for pillar ordering
- `enforcement` block — `window_weeks` for lookback context

If pillars.json is missing, error and stop (same pattern as /gcd:status).

**Example:**

```bash
cat ~/your-repo/.planning/pillars.json
```

**Required fields:** `pillars` (array), `enforcement.window_weeks` (integer).

**Directory setup:** Ensure retros directory exists:

```bash
mkdir -p ~/your-repo/.planning/retros
```

---

## Step 3: Scan Sprint Pieces

Glob these directories for `.md` files:

```
~/your-vault/content/**/*.md
```

For each file:
1. Read frontmatter
2. If `sprint` field matches the target sprint: include
3. Extract: `status`, `review_decision`, `piece_id`, `pillar`, `platform`/`route`, `brief_slug`, file path

Also scan briefs directory for sprint-assigned briefs:
```
~/your-vault/briefs/*.md
```
Include briefs where `sprint` field matches target sprint.

**Route determination:**
- If `platform: linkedin` → route is `linkedin`
- If `type: newsletter` → route is `newsletter`
- If brief has `route` field → use brief's route (e.g., `essay`)
- Fallback: route is `unknown`

**Output:** Array of piece objects with all extracted fields.

---

## Step 4: Invoke gcd-metrics-analyst for Pipeline Metrics

Delegate pipeline metrics calculation to the `gcd-metrics-analyst` agent.

**Build piece file paths array** from the pieces scanned in Step 3 — collect all absolute file paths.

**Invoke gcd-metrics-analyst** via Task tool:

```
Task(
  prompt="Calculate pipeline metrics for sprint [YYYY-WNN].

Sprint identifier: [YYYY-WNN]
Pillars config: ~/your-repo/.planning/pillars.json
Retro history: ~/your-repo/.planning/retros/

Piece files for this sprint:
[List each file path from Step 3 scan]

Return pipeline_metrics YAML only (skip performance_summary — that will be requested separately after engagement metrics are collected).",
  subagent_type="gcd-metrics-analyst",
  model="sonnet",
  description="Pipeline metrics"
)
```

**Store the agent's `pipeline_metrics` response** — this feeds Step 5 display, Step 9 retro record, and Step 9.5 performance file.

**Derive `pillars_covered` from agent output:** Extract pillar names where `shipped > 0` from `pillar_coverage`.

---

## Step 5: Display Pipeline Performance Summary

Format the agent's `pipeline_metrics` output for terminal display (data-first, before qualitative prompts):

```
=== Sprint [YYYY-WNN] Retrospective ===

## Pipeline Performance

Throughput: [completed]/[started] pieces completed ([completion_rate]%)
- Started: [throughput.started] pieces
- Completed: [count of approved+published+measured] pieces
- Stalled: [throughput.stalled] pieces
- Cancelled: [throughput.cancelled] pieces

Gate Performance:
- Gate 1 first-pass: [gate_performance.first_pass_rate]%
- Revision rate: [gate_performance.revision_rate]%
- Escalations: [gate_performance.escalation_count]

Route Performance:
| Route | Started | Completed | Rate |
|-------|---------|-----------|------|
[one row per route from route_performance]

Pillar Coverage:
| Pillar | Status | Piece(s) |
|--------|--------|----------|
[one row per pillar from pillar_coverage, ✓ shipped or ✗ not shipped]

Coverage: [N]/[total_pillars] pillars shipped
```

**Empty sprint handling:** If zero pieces found, display: "Empty sprint — no pieces assigned to [YYYY-WNN]." Prompt: "Why was this sprint empty? (Planned break? Pipeline stall?)" Capture response and write minimal retro file with zero metrics and the explanation.

---

## Step 6.0: Load LinkedIn Metrics + Post Text

Before collecting engagement metrics, build a joined dataset of LinkedIn metrics and post text.

### 6.0a: Load JSONL metrics

1. **Read** `~/your-vault/data/linkedin-metrics.jsonl` (one JSON object per line)
2. **Parse** all lines. Each line is a JSON object with fields including `activityId`, `impressions`, `reactions`, `comments`, `shares`, `reactionBreakdown`, `postUrl`, `contextDescription`, `collectedAt`.
3. **Deduplicate** posts by `activityId`: if multiple snapshots exist for the same `activityId`, keep the highest value for each metric field across all snapshots (highest `impressions`, highest `reactions`, etc. — merge across snapshots, not just "latest wins").
4. **Build lookup:** `metricsById` — a map of `{ activityId → { impressions, reactions, comments, shares, reactionBreakdown, postUrl, contextDescription } }`
5. **If file doesn't exist or is empty:** Log "No LinkedIn metrics data found — falling back to manual entry for all pieces." Set `metricsById` to empty map. Skip Step 6.0b.

### 6.0b: Load Shares.csv for post text

1. **Find latest export:** Glob `~/your-vault/04-Resources/linkedin-data/export-archive/*/Shares.csv`. Sort directories by name descending (newest date first). Use the first match.
2. **Parse** the CSV. Each row has: `Date`, `ShareLink` (URL-encoded, contains `urn:li:share:NNNNN`), `ShareCommentary` (post text), `SharedUrl`, `MediaUrl`, `Visibility`.
3. **Extract share IDs:** URL-decode `ShareLink`, extract the numeric ID after `urn:li:share:`.
4. **Join to JSONL metrics by 7-digit prefix:** The first 7 digits of a `share` ID match the first 7 digits of the corresponding `activity` ID. For each Shares.csv row, find the matching `activityId` in `metricsById` by prefix.
5. **Build enriched lookup:** `enrichedMetrics` — a map of `{ activityId → { ...metrics, postText (first 200 chars of ShareCommentary, whitespace-normalized) } }`
6. **If Shares.csv doesn't exist:** Log "No LinkedIn data export found — auto-matching by content unavailable." Proceed without post text (manual matching fallback in Step 6).
7. **If JSONL loading or CSV parsing fails on individual lines:** Skip bad lines and log warnings — do not abort the entire load.

---

## Step 6: Collect Engagement Metrics

Auto-fill engagement metrics for eligible pieces by matching piece content to LinkedIn post data. Falls back to manual entry only when auto-matching fails.

**Scope:** Only pieces with status in [`approved`, `published`, `measured`]. Do not process draft/reviewed pieces — they have not been published.

### Auto-matching flow (LinkedIn pieces)

For each eligible piece where `platform` is `linkedin` and `enrichedMetrics` is non-empty:

#### Path A: Existing `post_url` in frontmatter

If the piece already has a `post_url` field:
- Extract the activity ID from the URL
- Look up in `metricsById`
- **If found:** auto-fill metrics directly (no user interaction)
- **If not found:** fall through to Path B

#### Path B: Content-based matching

If no `post_url` or Path A lookup failed:
1. **Extract matching text from piece:** Read the piece body (below frontmatter). Find the first substantial text line — skip markdown headings (`#`), metadata lines (`**Publishes:**`, `**Purpose:**`), horizontal rules (`---`), and blank lines. Take the first 100 characters of the first real content line, whitespace-normalized.
2. **Fuzzy match against `enrichedMetrics`:** Compare the extracted text against each entry's `postText`. Match if the piece text appears as a substring of the post text (or vice versa), case-insensitive, after whitespace normalization and stripping leading/trailing quotation marks.
3. **If exactly one match:** auto-fill metrics and write `post_url` to frontmatter.
4. **If multiple matches:** log warning "Multiple matches for [piece_id] — skipping auto-fill, manual entry needed." Fall through to manual entry.
5. **If no match:** fall through to manual entry.

#### Path C: Manual entry (fallback for non-LinkedIn or unmatched pieces)

For pieces where auto-matching was unavailable or failed:

Display:

```
---
[piece_id]: "[brief_slug]" ([pillar]) — [platform] — status: [status]
```

Then prompt:

```
Enter engagement metrics for [piece_id]? [y/N/platform name]:
```

- `y` or Enter with no platform specified: Use the piece's `platform` field as the platform key
- A platform name (e.g., `twitter`, `linkedin`): Use that as the platform key (for cross-posted content)
- `N` or Enter: Skip this piece (no metrics entered)

**If user enters a platform (or y):**

Prompt for each metric sequentially. Enter to skip each individual metric (skip = no data for that field, distinct from 0):

```
  Impressions [Enter to skip]:
  Reactions [Enter to skip]:
  Comments [Enter to skip]:
  Shares [Enter to skip]:
```

**Parsing rules:**
- Empty input = skip that metric field entirely (do not write it)
- `0` = write 0 (means "checked, zero engagement")
- Any positive integer = write that value
- Non-numeric input = warn "Invalid number, skipping field" and treat as skip

**If ALL four metrics were skipped** (user hit Enter four times): Treat as if the piece was skipped entirely (no platform key written). Log: "All metrics skipped for [piece_id] — no data recorded."

**Validation after all four metrics collected:**

If any metric value exceeds impressions (and impressions was entered):
- Warn: "Warning: [metric] ([value]) exceeds impressions ([impressions]). This may be inaccurate."
- Prompt: "Continue anyway? [Y/n]: "
- If user says n: Re-prompt for that metric only
- If user says Y or Enter: Accept the values

### Write metrics to frontmatter (applies to both auto-fill and manual entry)

**Calculate engagement_rate:**
- If impressions > 0: (reactions + comments + shares) / impressions (only include metrics that were entered, not skipped)
- If impressions = 0 or was skipped: engagement_rate = 0.0

**Write to piece frontmatter immediately (not batched):**

Read the piece file, parse frontmatter, add or update the `engagement_metrics` nested object:

```yaml
engagement_metrics:
  [platform]:
    impressions: [value]
    reactions: [value]
    comments: [value]
    shares: [value]
    engagement_rate: [calculated]
    collected_date: "[ISO 8601 now]"
```

If metrics came from auto-fill (Paths A or B), also write `post_url` to frontmatter (if not already present):

```yaml
post_url: "https://www.linkedin.com/feed/update/urn:li:activity:NNNN..."
```

Preserve any existing engagement_metrics for other platforms (multi-platform support).

**Status transition:**
- If piece status is `published` and at least one metric was written: transition status to `measured`
- If piece status is `approved`: leave as `approved` (not yet published, metrics are pre-publish baseline)
- If piece status is already `measured`: leave as `measured` (allow metric updates/additions)

### Display summary (after all pieces processed)

After processing all eligible pieces, display a single summary table:

```
## Engagement Metrics — Auto-Fill Results

| Piece    | Match    | Impressions | Reactions | Comments | Shares | Eng. Rate |
|----------|----------|-------------|-----------|----------|--------|-----------|
| W09-01   | auto     | 13,372      | 13        | 0        | 0      | 0.10%     |
| W09-02   | manual   | 500         | 12        | 3        | 1      | 3.20%     |
| W09-03   | —        | (skipped)   |           |          |        |           |

Auto-filled: N pieces | Manual: N pieces | Skipped: N pieces | Failed to match: N pieces
```

If any pieces failed to auto-match, list them:
```
Could not auto-match (manual entry prompted):
  - [piece_id]: no content match found in Shares.csv
```

**Track for retro record:**
Build an array of pieces that received metrics (piece_id, platforms measured, source: "auto"|"manual") and a count of pieces skipped. Pass both to the retro record writing step.

### Important constraints for this step

- Write frontmatter per piece immediately after auto-fill — do not batch (prevents data loss on errors)
- Do NOT prompt for pieces at draft or reviewed status
- Do NOT block retro if no pieces can be matched
- Do NOT use platform-specific labels (always impressions/reactions/comments/shares regardless of platform)
- Preserve existing engagement_metrics when adding a new platform key
- Auto-fill is silent per piece — no confirm/skip prompts. User sees the summary table at the end.
- Manual entry only triggers as a fallback when auto-matching fails or for non-LinkedIn platforms

---

## Step 6.5: Invoke gcd-metrics-analyst for Performance Analysis

After engagement metrics are collected, delegate performance analysis to the `gcd-metrics-analyst` agent.

**Purpose:** Users see data-informed insights about what content patterns are working (top performers) and what patterns are underperforming (bottom performers), enabling strategic iteration decisions.

**When to run:** After Step 6 (Collect Engagement Metrics) so freshly-entered data is included. Runs BEFORE Step 7 (Handle Incomplete Pieces) so performance context informs carry-over decisions.

**Invoke gcd-metrics-analyst** via Task tool:

```
Task(
  prompt="Analyze engagement performance for sprint [YYYY-WNN].

Sprint identifier: [YYYY-WNN]
Pillars config: ~/your-repo/.planning/pillars.json
Retro history: ~/your-repo/.planning/retros/

Piece files (same set from Step 3, now with freshly-written engagement_metrics):
[List each file path from Step 3 scan]

Content directories for rolling window scan:
  - ~/your-vault/content/**/*.md

Return performance_summary YAML.",
  subagent_type="gcd-metrics-analyst",
  model="sonnet",
  description="Performance analysis"
)
```

**Store the agent's `performance_summary` response** — this feeds Step 6.5 display, Step 9 retro record, and Step 9.5 performance file.

### Display Performance Analysis

Format the agent's `performance_summary` output for terminal display:

```
## Performance Analysis (last 4 weeks)

Metrics coverage: [coverage_pct]% ([pieces_analyzed]/[pieces_eligible] pieces)

### By Route

[For each route in route_comparison:]
**[Route]** — avg engagement rate: [avg_engagement_rate]% [trend arrow]
  Pieces: [pieces]

### High Performers (top quartile)
| Piece | Route | Pillar | Engagement Rate | Composite Score |
|-------|-------|--------|-----------------|-----------------|
[From high_performers array, max 5 rows]

### Low Performers (bottom quartile)
| Piece | Route | Pillar | Engagement Rate | Composite Score |
|-------|-------|--------|-----------------|-----------------|
[From low_performers array, max 5 rows]

### Insights
[Display each insight string from the agent's insights array]
```

**Cold start handling:** If agent returns `status: "insufficient_data"`, display coverage stats and skip performer tables. Route comparison still displays if any routes have data.

**Trend arrow mapping:** `up` → `↑`, `down` → `↓`, `stable` → `→`, `new` → `—`

### Important Constraints for Step 6.5

- Do NOT modify any files during this step — this is display-only analysis
- Do NOT block retro if insufficient data — the agent degrades gracefully
- Do NOT re-compute metrics inline — trust the agent's structured output

---

## Step 6.6: Extract Performance Lessons

After the metrics analyst returns `performance_summary` (Step 6.5), extract actionable patterns into editorial-lessons.md.

**When to run:** Only if ALL of the following are true:
- `performance_summary.status == "analyzed"` (not `insufficient_data`)
- `coverage_pct >= 0.5`

If either condition fails, log: "Skipping lesson extraction ([reason])." and proceed to Step 6.7.

### Flow

1. Read `~/your-vault/03-Areas/professional-content/strategy/editorial-lessons.md`
2. Take the `insights` array from `performance_summary` (2–4 strings)
3. For each insight, check against existing content:
   - Scan all ALWAYS/NEVER rules in the file
   - Scan all existing `## Candidates` entries
   - If the insight is already captured (same core idea, even if worded differently), skip it
4. Infer a category for each new insight from its content:
   - **Hooks** — about opens, headlines, or first lines
   - **Voice** — about tone, specificity, or word choice
   - **Structure** — about format, length, or paragraph patterns
   - **Platform** — about platform-specific behavior or trends
   - **Performance Pattern** — about route × pillar combos, engagement trends, or audience patterns
5. Append new entries to the `## Candidates (promote or discard)` section:
   ```
   - [YYYY-MM-DD] [Category] — [insight text] (auto: retro YYYY-WNN, N pieces analyzed)
   ```
6. Write the updated file. Update `updated:` date in frontmatter.
7. Display what was added:
   ```
   ## Lesson Candidates Added

   + [Category] — [insight text]
   + [Category] — [insight text]

   (N new candidates added to editorial-lessons.md)
   ```
   Or if no new candidates: "No new lesson candidates — all insights already captured."

### Guardrails

- Max 3 new candidates per retro — if more than 3 insights are novel, pick the 3 most actionable
- Never auto-promote to ALWAYS/NEVER — candidates stay in `## Candidates` until a human promotes or discards them
- Never remove or edit existing ALWAYS/NEVER rules or existing candidates
- Never modify anything above the `## Candidates` section

---

## Step 6.7: Annotate Exemplar Performance

After lesson extraction, update exemplar entries that received engagement metrics in Step 6.

**When to run:** Only if exemplar files exist at `~/your-vault/03-Areas/professional-content/strategy/exemplars/*.md`. If the directory is empty or missing, log: "No exemplar files found — skipping exemplar annotation." and proceed to Step 7.

### Flow

1. For each piece that received engagement metrics in Step 6:
   a. Determine which exemplar file to check based on the piece's route/platform:
      - `linkedin` → `exemplars/linkedin.md`
      - `twitter` → `exemplars/twitter.md`
      - `newsletter` → `exemplars/newsletter.md`
      - `essay` → `exemplars/essay.md`
      - Other routes → skip (no exemplar file expected)
   b. Read the exemplar file
   c. Search for the piece's title or brief_slug in `##` headings
   d. If found, add or update a `**Performance:**` line immediately after the `**Why it worked:**` line:
      ```
      - **Performance:** [impressions] impressions, [engagement_rate]% engagement rate ([quartile label]) — collected YYYY-MM-DD
      ```
   e. Quartile label logic:
      - If the piece appears in `performance_summary.high_performers`: use `(top quartile)`
      - If the piece appears in `performance_summary.low_performers`: use `(bottom quartile)`
      - Otherwise: omit the quartile label entirely

2. **Bottom-quartile exemplar warning:**
   If a piece is both an exemplar (found in an exemplar file heading) AND in `performance_summary.low_performers`:
   ```
   WARNING: Exemplar "[title]" is in bottom quartile ([engagement_rate]% engagement rate).
   Consider replacing with a higher performer. Replace? [y/N]:
   ```
   - If `N` or Enter: keep the exemplar, add the Performance line with bottom quartile label, continue
   - If `y`: show a numbered list of pieces from `performance_summary.high_performers`:
     ```
     High performers available:
     1. [piece_id] — "[title]" ([route], [pillar], [engagement_rate]%)
     2. [piece_id] — "[title]" ([route], [pillar], [engagement_rate]%)

     Which piece should replace "[title]"? [number]:
     ```
     Then prompt: `"Why it worked" sentence for the new exemplar: `
     Replace the old exemplar's `##` section with the new piece's heading, hook pattern, "Why it worked" sentence, and Performance line. Remove the old section entirely.

3. Write updated exemplar file(s). Update `updated:` date in frontmatter.

4. Display summary:
   ```
   ## Exemplar Annotations

   Updated: [N] exemplar(s) with performance data
   [For each updated exemplar:]
     ~ [title] — [impressions] impressions, [engagement_rate]% ([quartile])

   [If any replacements were made:]
   Replaced: [old title] → [new title] in [exemplar file]
   ```

### Important Constraints for Step 6.7

- Only annotate exemplars that match pieces measured in THIS retro session (Step 6)
- Never remove exemplar entries unless the user explicitly approves a replacement
- Preserve all other content in the exemplar file — only modify/add `**Performance:**` lines or replace specific `##` sections
- If `performance_summary.status == "insufficient_data"`, skip quartile labels entirely (still add raw metrics if available)

---

## Step 7: Handle Incomplete Pieces

For each piece where status is `draft` or `reviewed` (stalled/incomplete):

Display the piece info and prompt:

```
[piece_id]: "[brief_slug]" ([pillar]) — stalled at [status]

Options:
  [c] Carry over to next sprint (clears sprint fields, returns to queue)
  [x] Cancel (marks cancelled, archives piece)
  [k] Keep in [sprint] (leaves sprint fields intact)

Choice:
```

Based on user choice:

### Carry over (c)

- Read the piece file
- Remove `sprint` field from frontmatter
- Remove `piece_id` field from frontmatter
- Remove `scheduled` field from frontmatter
- KEEP `pillar` field (hint for next planning session)
- KEEP `status`, `review_decision`, and all other fields as-is
- Write the updated file
- Log: "Carried over [piece_id] to brief queue"

### Cancel (x)

- Read the piece file
- Set `status: cancelled` in frontmatter
- Remove `sprint` field from frontmatter
- Remove `piece_id` field from frontmatter
- Remove `scheduled` field from frontmatter
- Write the updated file
- Log: "Cancelled [piece_id]"
- Add to `cancelled_pieces` array for retro record

### Keep (k)

- No changes
- Log: "Kept [piece_id] in [sprint]"

**Prompt for why:** After user chooses carry-over or cancel, prompt: "Why did [piece_id] stall? (Route wrong? Topic weak? Time constraint?): " Capture each response for retro record.

---

## Step 8: Collect Qualitative Notes

Adaptive depth based on sprint size:

### If completed_pieces <= 2 (per-piece walkthrough)

- For each completed piece, display: `[piece_id]: "[brief_slug]" ([pillar])`
- Prompt: "Anything to note about this piece? [Enter to skip]: "
- Capture each response (skip if empty)

### If completed_pieces >= 3 (sprint-level only)

- Prompt: "Sprint-level observations — what worked, what didn't, any patterns?"
- Capture response (free-form)

### For EVERY stalled piece (regardless of sprint size)

This should have been captured in Step 7 context. If user chose carry-over or cancel, the "why" response is already captured.

### Actions for Next Sprint (optional)

- Prompt: "Actions for next sprint? (e.g., validate essay hooks earlier) [Enter to skip]: "
- If provided, format as markdown checklist items

---

## Step 9: Write Retro Record

Construct the retro file. Write ONCE after all data is collected (metrics + qualitative notes).

File path: `~/your-repo/.planning/retros/[sprint].md` (e.g., `.planning/retros/2026-W08.md`)

### YAML Frontmatter (structured data for agent parsing)

```yaml
---
sprint: "YYYY-WNN"
closed_date: "YYYY-MM-DDThh:mm:ss±HH:MM"
pillars_covered: ["Pillar Name 1", "Pillar Name 2"]
throughput:
  started: N
  completed: N
  completion_rate: 0.NN
gate_performance:
  first_pass_rate: 0.NN
  revision_rate: 0.NN
route_performance:
  route_name:
    started: N
    completed: N
    completion_rate: 0.NN
stalled_pieces: ["WNN-NN"]
cancelled_pieces: ["WNN-NN"]
engagement:
  pieces_measured: N          # count of pieces that received metrics in this retro
  pieces_skipped: N           # count of eligible pieces where user skipped metrics
  platforms_measured: ["linkedin", "twitter"]  # unique platforms with metrics
  avg_engagement_rate: 0.NNNN  # average engagement_rate across all measured platforms
performance:
  window: "4-sprint"
  pieces_analyzed: N          # pieces with engagement_metrics in 28-day window
  pieces_eligible: N          # total published+measured in 28-day window
  coverage_pct: 0.NN          # pieces_analyzed / pieces_eligible
  high_performers:
    - piece_id: "WNN-NN"
      route: "twitter"
      pillar: "Pillar One"
      engagement_rate: 0.NNNN
      composite_score: 0.NNNN
  low_performers:
    - piece_id: "WNN-NN"
      route: "linkedin"
      pillar: "Pillar Three"
      engagement_rate: 0.NNNN
      composite_score: 0.NNNN
  route_comparison:
    twitter:
      avg_engagement_rate: 0.NNNN
      trend: "↑"              # ↑ ↓ → or —
      pieces: N
    linkedin:
      avg_engagement_rate: 0.NNNN
      trend: "→"
      pieces: N
---
```

**`avg_engagement_rate` calculation:** Sum all `engagement_rate` values from all pieces/platforms measured in this retro session, divide by count of platform entries. If zero pieces measured, use 0.0.

**`performance` block population:** Use the `performance_summary` response from the gcd-metrics-analyst agent (Step 6.5):
- If agent returned `status: "insufficient_data"`, write:
  ```yaml
  performance:
    window: "4-sprint"
    pieces_analyzed: N
    pieces_eligible: N
    coverage_pct: 0.NN
    status: "insufficient_data"
  ```
- If agent returned `status: "analyzed"`, populate full structure from agent's `high_performers`, `low_performers`, and `route_comparison` arrays

### Markdown Body (human-readable narrative)

```markdown
# Sprint [YYYY-WNN] Retrospective

**Closed:** YYYY-MM-DD
**Week:** Mon DD Mon – Sun DD Mon, YYYY

---

## Throughput

- **Started:** N pieces
- **Completed:** N pieces (NN%)
- **Stalled:** N pieces
- **Cancelled:** N pieces

## Gate Performance

- **Gate 1 first-pass:** N/N pieces (NN%)
- **Needed revision:** N/N pieces

## Route Performance

| Route | Started | Completed | Rate |
|-------|---------|-----------|------|
[rows]

## Pillar Coverage

| Pillar | Status | Piece(s) |
|--------|--------|----------|
[rows with ✓ or ✗]

**Coverage:** N/N pillars shipped.

---

## Engagement Metrics

**Measured:** N/N eligible pieces ([platforms list])

| Piece | Platform | Impressions | Reactions | Comments | Shares | Eng. Rate |
|-------|----------|-------------|-----------|----------|--------|-----------|
[one row per piece-platform combination that received metrics]

[If any pieces were skipped:]
**Metrics still needed:** [N] pieces skipped — run `/gcd:retro [sprint]` to add metrics later, or edit piece frontmatter manually.

[If no pieces were measured:]
No engagement metrics collected this sprint.

---

## Performance Analysis

[If cold start (< 8 measured pieces in 28-day window):]
Insufficient data for performance ranking (N/8 pieces with metrics needed).

**Metrics coverage:** N/M pieces (P%)

[If sufficient data (>= 8 measured pieces), display full analysis:]

**Metrics coverage:** N/M pieces (P%)

### By Route

**Twitter** — avg engagement rate: X.X% [trend arrow]
  Pieces: N | Impressions: NNN,NNN | Engagement rate range: X.X%–X.X%
  By pillar:
    Pillar One: X.X% avg (N pieces)
    Career & Leadership: X.X% avg (N pieces)
  Top tags: #tag1 (X.X%, N pieces), #tag2 (X.X%, N pieces)

**LinkedIn** — avg engagement rate: X.X% [trend arrow]
  [same structure as Twitter]

[Repeat for each route with measured pieces]

### High Performers (top quartile)

| Piece | Route | Pillar | Engagement Rate | Composite Score |
|-------|-------|--------|-----------------|-----------------|
[top N pieces by composite_score, max 5 rows]

### Low Performers (bottom quartile)

| Piece | Route | Pillar | Engagement Rate | Composite Score |
|-------|-------|--------|-----------------|-----------------|
[bottom N pieces by composite_score, max 5 rows]

### Pieces Still Needing Metrics

[If pieces_eligible > pieces_analyzed:]
N pieces still need engagement metrics: [piece_id list, max 10 shown]

---

## Qualitative Notes

### What Worked

[user notes or "(no notes provided)"]

### What Didn't Work

[user notes or "(no notes provided)"]

### Stalled Pieces

[For each stalled piece: piece_id, brief_slug, pillar, status, why it stalled, action taken (carried over/cancelled/kept)]

### Sprint-Level Observations

[user notes or "(no notes provided)"]

---

## Actions for Next Sprint

[Checklist items or "(no actions noted)"]

---

*Retro generated by /gcd:retro*
```

**Date formatting:** Calculate the week range for the "Week:" line. ISO week YYYY-WNN corresponds to Monday of that week. Calculate Monday and Sunday dates.

---

## Step 9.5: Write Performance Summary File

Write a separate structured performance summary file that the sprint-planner agent consumes during next sprint planning. This file is separate from the retro record to maintain separation of concerns (retro owns analysis, sprint-planner owns scoring).

**File path:** `.planning/retros/YYYY-WNN-performance.md` (e.g., `.planning/retros/2026-W08-performance.md`)

**File format — YAML frontmatter only (no markdown body):**

```yaml
---
sprint: "YYYY-WNN"
generated: "ISO 8601 timestamp"
window: "4-sprint"
pieces_analyzed: N
pieces_eligible: N
coverage_pct: 0.NN

high_performers:
  - route: "twitter"
    pillar: "Pillar One"
    tags: ["AI", "agents"]
    avg_engagement_rate: 0.NNNN
    pieces: N
  - route: "linkedin"
    pillar: "Pillar Three"
    tags: ["hiring", "leadership"]
    avg_engagement_rate: 0.NNNN
    pieces: N

low_performers:
  - route: "twitter"
    pillar: "Pillar Two"
    avg_engagement_rate: 0.NNNN
    pieces: N

route_comparison:
  twitter:
    avg_engagement_rate: 0.NNNN
    trend: "↑"
    pieces: N
  linkedin:
    avg_engagement_rate: 0.NNNN
    trend: "→"
    pieces: N

insights:
  - "Twitter threads on Pillar One consistently outperform (3.8% avg vs 2.1% overall)"
  - "LinkedIn Career & Leadership posts trending up"
  - "E-Commerce content underperforming on Twitter — consider LinkedIn route instead"
---
```

**Key rules:**
- Use the `performance_summary` response from the gcd-metrics-analyst agent (Step 6.5) — do NOT re-compute or re-scan
- high_performers and low_performers come directly from the agent's structured output
- insights array comes directly from the agent's `insights` field
- route_comparison comes directly from the agent's `route_comparison` field
- If agent returned `status: "insufficient_data"`, write minimal file with empty arrays

**If cold start (< 8 measured pieces in 28-day window):**

Write minimal file:
```yaml
---
sprint: "YYYY-WNN"
generated: "ISO 8601 timestamp"
window: "4-sprint"
pieces_analyzed: N
pieces_eligible: N
coverage_pct: 0.NN
status: "insufficient_data"
high_performers: []
low_performers: []
route_comparison: {}
insights: []
---
```

Always write route_comparison even in cold start (route metrics work with any N).

---

## Step 10: Git Commit

Check commit_docs setting:
- Read `.planning/config.json` for `commit_docs` (default: true)
- If `.planning` is gitignored, set commit_docs to false

If commit_docs is true:

### Commit retro file, performance summary, and feedback loop files

```bash
git add .planning/retros/[sprint].md .planning/retros/[sprint]-performance.md
git add ~/your-vault/03-Areas/professional-content/strategy/editorial-lessons.md
git add ~/your-vault/03-Areas/professional-content/strategy/exemplars/*.md
git commit -m "docs(sprint): [sprint] retrospective

Sprint [sprint] closed
- Throughput: [completion_rate]% ([completed]/[started] pieces)
- Pillar coverage: [N]/[total] pillars shipped
- Engagement: [pieces_measured] pieces measured
- Performance: [N] pieces analyzed, [high_count] high/[low_count] low performers identified
- [carried_over] carried over, [cancelled_count] cancelled"
```

### Commit modified piece files (if any carry-over or cancel actions from Step 7)

```bash
git add [modified piece file paths]
git commit -m "chore(sprint): close [sprint] — carry-over and cancellation updates"
```

### Commit piece files modified by engagement metric collection (if any)

If any pieces had their frontmatter updated with engagement_metrics or status changed to measured in Step 6:

```bash
git add [piece files with new engagement_metrics or measured status]
git commit -m "chore(sprint): [sprint] engagement metrics — [pieces_measured] pieces measured"
```

If commit_docs is false, log: "Skipping git commit (commit_docs: false)"

---

## Step 11: Display Closing Summary

```
=== Sprint [sprint] Closed ===

Retro saved to: .planning/retros/[sprint].md

Summary:
- Throughput: [completed]/[started] ([completion_rate]%)
- Pillar coverage: [N]/[total] pillars
- Engagement: [pieces_measured] pieces measured, avg [avg_engagement_rate]% engagement rate
- Performance: [N] high performers, [N] low performers identified ([N] pieces analyzed)
  [If cold start:] Performance: insufficient data ([N]/8 pieces with metrics needed)
- Carried over: [N] pieces
- Cancelled: [N] pieces

[If pieces_skipped > 0:]
Note: [pieces_skipped] piece(s) still need engagement metrics.
Add metrics by editing piece frontmatter directly (see frontmatter-spec.md).

Sprint [sprint] is now formally closed.
Run /gcd:status to see the updated view.
Run /gcd:plan-sprint to start the next sprint.
```

---

## Important Constraints

- Do NOT overwrite existing retro files — error and stop if file exists
- Do NOT write to SPRINT.md — that is /gcd:status domain
- Do NOT modify piece content (only frontmatter) — carry-over and cancel affect frontmatter fields only
- Do NOT skip the overwrite check (Step 1) — retro is a one-time close ceremony
- Do NOT count approved/published/measured pieces as "stalled" — they are completed
- Do NOT count cancelled pieces as "stalled" — cancellation is a deliberate decision
- Completed = status in [approved, published, measured] — all are terminal success states from the GCD pipeline perspective

---

## Anti-Patterns

- Prompting user for throughput or revision counts. These are auto-calculated from frontmatter scans.
- Writing the retro file before collecting qualitative notes. Collect ALL data first, write ONCE at the end.
- Blocking sprint close on incomplete work. Incomplete pieces are expected — offer carry-over/cancel/keep options.
- Calculating completion rate with only `published` pieces. Include `approved` and `measured` too.
- Counting exact revision cycles via git history parsing. Approximate from `review_decision` field presence.
- Creating separate retro files per piece. One retro file per sprint.

---

## Reference Data

### Lifecycle Status Values (including cancelled state)

| Status | Meaning |
|--------|---------|
| `stub` | Brief captured, not yet in sprint or drafting |
| `draft` | In-progress drafting — piece assigned to sprint |
| `reviewed` | Editor-in-chief Gate 1 passed |
| `approved` | Human approved via /gcd:approve — publish-ready |
| `published` | Live on platform |
| `measured` | Metrics captured — terminal state |
| `cancelled` | Deliberately abandoned — terminal state |

### Files

- **pillars.json:** `~/your-repo/.planning/pillars.json`
- **Content files:** `~/your-vault/03-Areas/professional-content/`
- **Brief queue:** `~/your-vault/briefs/`
- **Retro output:** `~/your-repo/.planning/retros/`
- **Config:** `~/your-repo/.planning/config.json`
- **gcd-metrics-analyst agent:** `~/.claude/agents/gcd-metrics-analyst.md`
