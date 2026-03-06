---
name: gcd-produce
description: Draft content for a sprint-planned piece OR assemble weekly newsletter from approved pieces. Supports 4 routes - piece-id dispatch (linkedin/essay/twitter-thread via brief), or --newsletter flag (assemble from approved sprint pieces). Updates brief status for piece routes. Use when the user runs /gcd:produce.
tools: Read, Write, Glob
---

# GCD Produce

Production engine for sprint-planned content pieces and weekly newsletters. Supports four modes:
1. **LinkedIn route** (piece-id) — gcd-producer drafts post from brief
2. **Substack route** (piece-id) — gcd-researcher → user gate → gcd-producer drafts essay from brief
3. **Twitter thread route** (piece-id) — gcd-producer drafts thread from brief
4. **Newsletter route** (--newsletter sprint-id) — assembles repurposed highlights + original section from approved sprint pieces

Piece routes create content files with full GCD frontmatter and transition briefs from `stub` to `draft`. Newsletter route assembles approved pieces into a weekly digest.

## How to Use

```
/gcd:produce [piece-id]               # Draft a sprint-planned piece (e.g., /gcd:produce W08-01)
/gcd:produce --newsletter 2026-W08    # Assemble weekly newsletter from approved pieces
```

## Important Constraints

- Do NOT invoke the gcd-reviewer agent — that is Phase 4 (/gcd:review).
- Do NOT change `status` to anything other than `draft` — Phase 3 owns only `stub → draft`.
- Do NOT write to SPRINT.md — that is /gcd:status domain.
- Do NOT proceed if brief is missing required fields (sprint, piece_id, pillar, scheduled, route).
- Do NOT overwrite existing content files without user confirmation.
- Do NOT hardcode pillar names or route-to-pillar mappings — route dispatch uses the brief's `route` field.
- Newsletter route requires approved pieces — do NOT assemble from draft or reviewed pieces.

---

## Behavior

Execute each step in order. Do not skip steps.

### Step 1: Parse Argument

Expect ONE of these command patterns:
- `/gcd:produce [piece-id]` (e.g., `/gcd:produce W08-01`) — draft a specific sprint piece
- `/gcd:produce --newsletter [sprint-id]` (e.g., `/gcd:produce --newsletter 2026-W08`) — assemble newsletter from approved sprint pieces

**If no arguments provided:**
```
Error: No argument provided.
Usage:
  /gcd:produce [piece-id]               # Draft a sprint-planned piece (e.g., W08-01)
  /gcd:produce --newsletter [sprint-id] # Assemble newsletter (e.g., 2026-W08)

Run /gcd:status to see current sprint pieces and their IDs.
```

**If `--newsletter` flag is present:**
- Extract the `sprint_id` string from the second argument (e.g., `2026-W08`)
- Validate format: `YYYY-WNN` (4-digit year, hyphen, W, 2-digit week)
- If format invalid: output "Error: Invalid sprint ID format. Expected YYYY-WNN (e.g., 2026-W08)" and STOP
- Set `route_mode` to `newsletter`
- Skip Steps 2-4, proceed directly to Step 6C

**If no `--newsletter` flag:**
- Extract the `piece_id` string from the argument (e.g., `W08-01`)
- Set `route_mode` to `piece`
- Continue to Step 2

### Step 2: Find the Brief

**Directory setup:** Before proceeding, ensure required directories exist:

```bash
mkdir -p ~/your-vault/content/$(date +%Y)
mkdir -p ~/your-repo/.planning/retros
```

These directories are created idempotently (mkdir -p is safe to run repeatedly).

Glob: `~/your-vault/briefs/*.md`

For each file returned:
1. Read the full file content
2. Parse the YAML frontmatter (between the `---` delimiters)
3. Check if the `piece_id` field matches the provided argument (exact string match)

**If no match found:** Output this error and STOP:
```
Error: No brief found with piece_id [arg].
Run /gcd:status to see current sprint pieces and their IDs.
```

**If multiple matches found:** Output this error and STOP:
```
Error: Multiple briefs found with piece_id [arg]. piece_id must be unique.
Check ~/your-vault/briefs/ for duplicate piece_id values.
```

**Store:**
- Brief file path (absolute path)
- Full brief content (all text, including frontmatter)
- Brief body (all content below the closing `---` of frontmatter)
- All frontmatter fields: `sprint`, `piece_id`, `pillar`, `scheduled`, `route`, `topic`, `status`, and any others present

### Step 3: Validate Brief

Check that ALL of these fields are present and non-empty in the brief's frontmatter:
- `sprint`
- `piece_id`
- `pillar`
- `scheduled`
- `route`

If any field is missing or empty, output an error listing the missing fields and STOP:

```
Error: Brief [piece_id] is missing required fields: [field1, field2, ...]

These fields are required before production can begin.
Run /gcd:plan-sprint to assign this brief to a sprint first.
```

### Step 4: Check for Existing Output

Compute the output path based on the brief's `route` field (see route steps below for path construction rules). At this step, compute the path but do not write anything yet.

If a file already exists at that computed path:

```
Draft already exists at: [path]
Overwrite? [y/N]
```

Default to NO. If the user does not type `y` or `yes` (case-insensitive), STOP with:

```
Existing draft preserved. No changes made.
```

### Step 5: Route Dispatch

**If `route_mode` is `newsletter` (set in Step 1):**
- Proceed directly to Step 6C (Newsletter route)

**If `route_mode` is `piece`:**
- Read the brief's `route` field and dispatch:
  - `linkedin` → proceed to Step 6A (LinkedIn route)
  - `essay` → proceed to Step 6B (Substack route)
  - `twitter-thread` → proceed to Step 6D (Twitter thread route)
  - Any other value → output error and STOP:

```
Error: Unsupported route: [route value].
Supported routes: linkedin, essay, twitter-thread

Check the brief's route field at: [brief file path]
```

### Step 6A: LinkedIn Route

**Output path construction:**
1. Extract the date portion from the `scheduled` field (the `YYYY-MM-DD` portion at the start of the ISO 8601 datetime string)
2. Derive a slug from the brief's `topic` field:
   - Convert to lowercase
   - Replace spaces and any non-alphanumeric characters (except hyphens) with hyphens
   - Collapse consecutive hyphens into a single hyphen
   - Strip leading and trailing hyphens
3. Extract year from the date (first 4 characters)
4. Output path: `~/your-vault/content/{year}/{date}-LI-{slug}.md`

**Invoke gcd-producer agent** with this context passed inline:

```
You are producing a LinkedIn post for Your Name's GCD sprint.

Piece: {piece_id}
Pillar: {pillar}
Sprint: {sprint}
Scheduled: {scheduled}

Brief:
{full brief body — everything below the closing --- of the frontmatter}

Read the voice guide at ~/your-vault/09-Profile/voice-guide.md before drafting.

Output: Save to {computed output path}

Include this YAML frontmatter at the top of the file:
---
context: professional
type: social
platform: linkedin
pillar: "{pillar}"
sprint: "{sprint}"
piece_id: "{piece_id}"
status: draft
created: {today's date in YYYY-MM-DD format}
scheduled: "{scheduled}"
brief_slug: "{brief filename without date prefix and without .md extension}"
tags: [{relevant tags derived from topic and pillar, comma-separated, lowercase, hyphenated}]
---

Follow all platform-specific rules from the voice guide. The LinkedIn hook in the first 2 lines must pass the 140-character fold test (complete thought before the "see more" break). No external links in the post body — put links in the first comment. Target 1,300–2,000 characters for the post body.
```

After gcd-producer completes, proceed to Step 7.

### Step 6B: Substack Route

**Output path construction:**
1. Derive a slug from the brief's `topic` field:
   - Convert to lowercase
   - Replace spaces and any non-alphanumeric characters (except hyphens) with hyphens
   - Collapse consecutive hyphens into a single hyphen
   - Strip leading and trailing hyphens
2. Extract year from the `scheduled` date (first 4 characters)
3. Extract the date portion from the `scheduled` field (the `YYYY-MM-DD` portion)
4. Output path: `~/your-vault/content/{year}/{date}-SS-{slug}.md`

**Stage 1: Research**

Invoke the gcd-researcher agent with this context:

```
Research this topic for a Substack essay by Your Name.

Topic: {topic from brief}
Sprint: {sprint}
Piece: {piece_id}

Brief:
{full brief body — everything below the closing --- of the frontmatter}

Save your research brief to: ~/your-vault/01-Inbox/research-briefs/{today's date YYYY-MM-DD}-{slug}.md

Focus on: data points, counter-arguments, real examples, and specific trends that support or challenge this topic. Your Name's audience is marketing, e-commerce, and tech operators. Be opinionated — analyze and recommend, don't just summarize. Cite sources.
```

**User gate after research:**

After the gcd-researcher agent completes, show the user:

```
Research brief saved to: ~/your-vault/01-Inbox/research-briefs/{today's date}-{slug}.md

Continue to draft? [Y/n/feedback]
  Y or Enter  — proceed to drafting
  n           — stop here (research brief is preserved, no draft written)
  feedback    — provide notes to pass to the gcd-producer
```

- If the user types `n`: STOP. Output "Research brief preserved. Run `/gcd:produce {piece_id}` again when ready to draft."
- If the user provides feedback text: store it to include in the draft prompt below
- If the user types `Y` or presses Enter: proceed to Stage 2

**Stage 2: Draft**

Invoke the gcd-producer agent with this context:

```
You are producing a Substack essay for Your Name's GCD sprint.

Piece: {piece_id}
Pillar: {pillar}
Sprint: {sprint}
Scheduled: {scheduled}

Research brief: ~/your-vault/01-Inbox/research-briefs/{today's date}-{slug}.md — READ THIS FILE FIRST before drafting.

{If user provided feedback: "User notes for this draft: {feedback text}"}

Read the voice guide at ~/your-vault/09-Profile/voice-guide.md before drafting.

Output: Save to {computed output path}

Include this YAML frontmatter at the top of the file:
---
context: professional
type: insight
platform: substack
pillar: "{pillar}"
sprint: "{sprint}"
piece_id: "{piece_id}"
status: draft
title: "{best title variant — write 3 variants in the body with pattern labels, pick the strongest for frontmatter}"
subtitle: "{under 10 words, creates tension with title}"
slug: "{slug}"
author: "Your Name"
description: "{meta description for SEO, 140-160 characters}"
created: {today's date in YYYY-MM-DD format}
scheduled: "{scheduled}"
brief_slug: "{brief filename without date prefix and without .md extension}"
tags: [{relevant tags derived from topic and pillar, comma-separated, lowercase, hyphenated}]
image: ""
---

Write a long-form essay with headers, evidence, and a CTA. Follow all platform-specific rules from the voice guide. Include 3 title variants with pattern labels (contrarian, data-led, direct address, etc.) at the top of the body before the main essay content. The hook — title + subtitle + opening paragraph — must function as a three-part hook system where each element works independently.
```

After gcd-producer completes, proceed to Step 7.

### Step 6C: Newsletter Route

This step assembles a newsletter from approved sprint pieces for the target sprint_id set in Step 1.

**1. Find approved sprint pieces:**

Glob content directory:
- `~/your-vault/content/**/*.md`

For each file:
1. Read the YAML frontmatter
2. Check if `sprint` field matches the target sprint_id (e.g., `2026-W08`)
3. Check if `status` field is `approved`
4. If BOTH match, add to approved pieces list

**If no approved pieces found:**
```
No approved pieces for sprint {sprint_id}.

Approve pieces with /gcd:approve first, then re-run:
/gcd:produce --newsletter {sprint_id}
```
STOP.

**Store for each approved piece:**
- File path
- Platform (linkedin or substack)
- Title (if Substack: read from `title` field; if LinkedIn: derive from first 60 chars of post text)
- Piece ID (from `piece_id` field)
- Pillar (from `pillar` field)
- Full content body (everything below the closing `---` of frontmatter)

**2. Assemble highlights:**

For each approved piece, extract a highlight:

**LinkedIn pieces:**
- Read the post text (content body)
- Extract the first 2-3 sentences (approximately first 200 characters, break at sentence boundary)
- This is the "hook" of the LinkedIn post

**Substack pieces:**
- Extract `title` and `subtitle` from frontmatter
- Extract the first paragraph of the essay body (first block of text after any title variants section, before first header)

Format each highlight as:
```markdown
**{title or hook preview}** — {pillar}
{excerpt}
[Read more: {piece_id}]({relative path to piece})
```

**3. Draft original section:**

Invoke the gcd-producer agent with this context:

```
You are producing the original section of a weekly newsletter for Your Name's Pillar Four.

Sprint: {sprint_id}

Approved pieces this week:
{for each approved piece, list: piece_id, platform, pillar, title/hook preview}

Read the voice guide at ~/your-vault/09-Profile/voice-guide.md before drafting.

Write a SHORT original section (150-300 words max) that:
- Ties together the week's themes
- Adds one new insight or observation not covered in the individual pieces
- Uses Your Name's voice (direct, specific, contrarian)
- Ends with a forward-looking hook for next week

Return ONLY the original section text. Do not include frontmatter or the highlights section — those are assembled separately.
```

Store the agent's output as `original_section_text`.

**4. Compute output path:**

Path: `~/your-vault/content/{year}/{today's date}-SS-newsletter-{sprint_id}.md`

Example: `~/your-vault/content/2026/2026-03-01-SS-newsletter-2026-W09.md`

Ensure the year directory exists:
```bash
mkdir -p ~/your-vault/content/$(date +%Y)
```

**5. Compose newsletter file:**

Write the file with this structure:

```yaml
---
context: professional
type: newsletter
platform: substack
sprint: "{sprint_id}"
status: draft
created: {today's date in YYYY-MM-DD format}
tags: [newsletter, weekly, dgtl-dept]
---
```

Followed by:

```markdown
# Pillar Four Weekly — {sprint_id}

## This Week

{original_section_text from gcd-producer}

## From the Archive

{assembled highlights, one per approved piece}

---

*Published weekly. Reply to this email with thoughts.*
```

After file is written, proceed to Step 8 (skip Step 7 — newsletters have no originating brief to update).

### Step 6D: Twitter Thread Route

**Output path construction:**
1. Extract the date portion from the `scheduled` field (the `YYYY-MM-DD` portion at the start of the ISO 8601 datetime string)
2. Derive a slug from the brief's `topic` field:
   - Convert to lowercase
   - Replace spaces and any non-alphanumeric characters (except hyphens) with hyphens
   - Collapse consecutive hyphens into a single hyphen
   - Strip leading and trailing hyphens
3. Extract year from the date (first 4 characters)
4. Output path: `~/your-vault/content/{year}/{date}-TW-{slug}.md`

**Invoke gcd-producer agent** with this context passed inline:

```
You are producing a Twitter thread for Your Name's GCD sprint.

Piece: {piece_id}
Pillar: {pillar}
Sprint: {sprint}
Scheduled: {scheduled}

Brief:
{full brief body — everything below the closing --- of the frontmatter}

Read the voice guide at ~/your-vault/09-Profile/voice-guide.md before drafting.
Pay special attention to the Twitter-specific section.

Output: Save to {computed output path}

Include this YAML frontmatter at the top of the file:
---
context: professional
type: social
platform: twitter
pillar: "{pillar}"
sprint: "{sprint}"
piece_id: "{piece_id}"
status: draft
created: {today's date in YYYY-MM-DD format}
scheduled: "{scheduled}"
suggested_time: "{recommend a posting time in HH:MM AM/PM ET format based on topic and audience best practices}"
brief_slug: "{brief filename without date prefix and without .md extension}"
tags: [{relevant tags derived from topic and pillar, comma-separated, lowercase, hyphenated}]
---

CRITICAL TWITTER CONSTRAINTS:
- Each tweet max 280 characters (soft limit — flag if over, allow minor overages for manual trim)
- Emojis count as 2 characters each, links count as 23 characters regardless of length
- First tweet (hook) must pass the 140-character mobile fold test: complete thought that creates curiosity gap
- Number tweets with inline convention: 1/ [content], 2/ [content], etc. This IS the copy-paste format
- Hook must tease insight without giving it away — create a curiosity gap
- Thread length is brief-dependent: no fixed range, but every tweet must earn the next
- Links ONLY in final tweet or Thread Notes section (never mid-thread)
- Voice: conversational, punchy, compressed insight — shorter sentences than LinkedIn, same person, no filler
- Use white space and line breaks within tweets for mobile readability
- No essay transition words ("Furthermore," "Additionally,") — each tweet should feel like a standalone insight that connects to the thread

Format output as:

# [Topic] - Twitter Thread

## Thread

1/ [First tweet - hook, creates curiosity gap, max 140 chars for mobile fold]

2/ [Second tweet - body, max 280 chars]

N/ [Final tweet - CTA or question, max 280 chars]

## Thread Notes

**Suggested Time:** {Best time based on topic and audience}
**Hashtags:** {List with volume/relevance context}
**Engagement Strategy:** {Pinning, replying, timing notes}
**Link Placement:** {Where to put source links — reply to tweet 1, final tweet, etc.}

## Voice Check
- Opinionated but not preachy: [Y/N]
- Compressed insight (no filler): [Y/N]
- Hook creates curiosity gap: [Y/N]
- Clear POV: [Y/N]
- Each tweet earns the next: [Y/N]
```

After gcd-producer completes, proceed to Step 7.

### Step 7: Update Brief Status

**If `route_mode` is `newsletter`:** Skip this step entirely (newsletters have no originating brief). Proceed directly to Step 8.

**If `route_mode` is `piece`:**

1. Read the originating brief file (absolute path from Step 2) using the Read tool
2. Locate the YAML frontmatter block (between the `---` delimiters at the top of the file)
3. Update ONLY the `status` field: change the value from `stub` to `draft`
4. Preserve ALL other existing fields without modification — do not add, remove, or rename any other fields
5. Write the updated brief file back using the Write tool

**Frontmatter update rule:** Find the line `status: stub` in the frontmatter and replace it with `status: draft`. If `status` has a value other than `stub`, still update it to `draft` (production has now begun). Preserve all other lines exactly.

### Step 8: Confirm and Suggest Next Steps

**If `route_mode` is `newsletter`:**

```
Produced: Newsletter for {sprint_id}
Pieces included: {count} approved pieces
Output: {newsletter file path}

Next: Review the newsletter and publish when ready.
```

**If `route_mode` is `piece`:**

```
Produced: {piece_id} ({route} route)
Sprint: {sprint}
Pillar: {pillar}
Output: {content file path}
Brief updated: status → draft

Next: Run `/gcd:review {piece_id}` to gate-check this piece.
```

---

## Files

- **Brief queue:** `~/your-vault/briefs/*.md`
- **LinkedIn output:** `~/your-vault/content/YYYY/YYYY-MM-DD-LI-{slug}.md`
- **Substack output:** `~/your-vault/content/YYYY/YYYY-MM-DD-SS-{slug}.md`
- **Twitter output:** `~/your-vault/content/YYYY/YYYY-MM-DD-TW-{slug}.md`
- **Newsletter output:** `~/your-vault/content/YYYY/YYYY-MM-DD-SS-newsletter-{sprint}.md`
- **Research briefs:** `~/your-vault/01-Inbox/research-briefs/YYYY-MM-DD-{slug}.md`
- **gcd-producer agent:** `~/.claude/agents/gcd-producer.md`
- **gcd-researcher agent:** `~/.claude/agents/gcd-researcher.md`

## Anti-Patterns — Do NOT

- Invoke the gcd-reviewer agent. That is /gcd:review (Phase 4).
- Change `status` to anything other than `draft`. Phase 3 owns only `stub → draft`.
- Write to SPRINT.md. That is /gcd:status domain exclusively.
- Proceed if brief is missing required fields (sprint, piece_id, pillar, scheduled, route).
- Overwrite an existing content file without explicit user confirmation.
- Hardcode pillar names or route-to-pillar mappings. Always read route from the brief's `route` field.
- Assemble newsletters from draft or reviewed pieces. Newsletter route requires status: approved only.
- Skip the user gate between research and drafting in the essay route.
- Change any brief field other than `status` in Step 7.
