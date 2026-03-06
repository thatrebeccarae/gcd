---
name: gcd-approve
description: Human approval gate for reviewed content pieces. Shows draft preview and review summary, prompts for explicit confirmation, updates frontmatter to approved. Use when user runs /gcd:approve.
tools: Read, Write, Bash
---

# GCD Approve

Gate 2 of the two-gate quality system — the human approval checkpoint that no piece can bypass.

This skill provides the explicit confirmation gate after editor-in-chief review. It shows the draft content and review summary, prompts for user approval, validates/sets the publish date, and updates frontmatter to `status: approved`. Files never move — status lives in frontmatter only.

This is a human-only skill. No agent invocation. The whole point is human judgment.

## How to Use

```
/gcd:approve [piece-id]     # Approve a reviewed piece (e.g., /gcd:approve W08-01)
```

Run `/gcd:status` to see piece IDs and their current status.

## Important Constraints

- Do NOT approve pieces that are not in `reviewed` status — this is a strict gate.
- Do NOT invoke any agent — this is a human-only approval step.
- Do NOT skip the user confirmation prompt — nothing advances without explicit yes.
- Do NOT move the file — files never move. Status lives in frontmatter only.
- Do NOT write to SPRINT.md — that is /gcd:status domain.
- Do NOT modify draft content except for optional rejection feedback HTML comment.

---

## Behavior

Execute each step in order. Do not skip steps.

### Step 1: Parse Argument

Expect: `/gcd:approve [piece-id]` (e.g., `/gcd:approve W08-01`)

**If no argument provided:**
```
Error: No argument provided.
Usage: /gcd:approve [piece-id]

Run /gcd:status to see current sprint pieces and their IDs.
```
STOP.

Extract the `piece_id` string from the argument.

### Step 2: Find the Draft

Glob content directory:
- `~/your-vault/content/**/*.md`

For each file returned:
1. Read the full file content
2. Parse the YAML frontmatter (between the `---` delimiters)
3. Check if the `piece_id` field matches the provided argument (exact string match)
4. **For newsletters:** If the argument matches sprint format `YYYY-WNN` (e.g., `2026-W08`), also check the `sprint` field for a match (newsletters use `sprint` as their identifier, not `piece_id`)

**If no match found:** Output this error and STOP:
```
Error: No piece found with piece_id [arg]

Run /gcd:status to see available pieces and their IDs.
```

**If multiple matches found:** Output this error and STOP:
```
Error: Multiple files found with piece_id [arg]

This should not happen. Check for duplicate piece_id values in:
- ~/your-vault/content/
```

**Store:**
- File path (absolute path to the content file)
- Full file content (all text, including frontmatter)
- Content body (all content below the closing `---` of frontmatter)
- All frontmatter fields: `piece_id`, `sprint`, `platform`, `pillar`, `status`, `scheduled`, `review_decision`, `title` (if present), and any others

### Step 3: Validate Status

Read the `status` field from the frontmatter.

**STRICT GATE:** status MUST be `reviewed`.

**If status is `draft`:**
```
ERROR: Cannot approve piece [piece_id]

Current status: draft
Required status: reviewed

Run /gcd:review [piece_id] first to advance piece to reviewed status.
```
STOP.

**If status is `approved`:**
```
Piece [piece_id] is already approved.
```
STOP.

**If status is anything other than `reviewed`:**
```
ERROR: Cannot approve piece [piece_id]

Current status: [current status value]
Required status: reviewed

Only pieces that have passed editor-in-chief review can be approved.
```
STOP.

**Also validate `review_decision` field:**

The `review_decision` field should equal `pass` if status is `reviewed`. This is a defensive check — normally this state should be impossible if earlier skills worked correctly.

**If `review_decision` is `revise` or `escalate` but status is somehow `reviewed`:**
```
ERROR: Invalid state for piece [piece_id]

Status: reviewed
Review decision: [review_decision value]

This state should not happen. The review decision indicates the piece needs work, but the status says it passed.

Re-run /gcd:review [piece_id] to resolve this inconsistency.
```
STOP.

### Step 4: Display Approval Ceremony

Determine the content type from the `platform` frontmatter field:
- `platform: linkedin` → LinkedIn post
- `platform: substack` and `type: insight` → Substack article
- `platform: substack` and `type: newsletter` → Newsletter
- `platform: twitter` → Twitter thread

**Display this to the user:**

```
=== Approve for Publishing ===

Piece: [piece_id] ([title from frontmatter if present, otherwise first 60 chars of content body])
Sprint: [sprint]
Type: [platform/content type]
Pillar: [pillar]

Review Summary:
  Decision: pass
  [Note: full review scores are in the draft as HTML comments]

--- DRAFT PREVIEW ---

[First 500 words of content body, or full content if under 500 words]

[... trimmed for preview ...]

--- END PREVIEW ---

Approve this piece for publishing? [y/N]:
```

Wait for user input.

### Step 5: Handle Confirmation

**If user enters `y` or `yes` (case-insensitive):**
Proceed to Step 6.

**If user enters anything else (including empty/Enter, which defaults to N):**

Prompt:
```
Add rejection feedback? [y/N]:
```

**If user enters `y` or `yes`:**
- Prompt: `Feedback: `
- Read the user's feedback text (everything they type on the next line)
- Inject a review comment at the TOP of the content body (immediately after the closing `---` of frontmatter):
  ```html
  <!-- REVIEW: Approval Rejected - [user feedback] -->
  ```
- Update the `status` field in frontmatter to `draft` (revert from `reviewed`)
- Write the updated file back to the same location
- Output:
  ```
  Approval rejected. Piece reverted to draft status.
  Rejection feedback added as HTML comment at top of file.

  Address feedback and re-run /gcd:review [piece_id] when ready.
  ```
- STOP.

**If user enters anything else:**
- Update the `status` field in frontmatter to `draft` (revert from `reviewed`)
- Write the updated file back to the same location (no content modification)
- Output:
  ```
  Approval rejected. Piece reverted to draft status.

  Re-run /gcd:review [piece_id] when ready.
  ```
- STOP.

### Step 6: Prompt for Publish Date

Read the `scheduled` field from the frontmatter as the default value.

Prompt the user:
```
Publish date/time [default: {scheduled value from frontmatter}]:
```

**If user presses Enter (empty input):**
Use the existing `scheduled` value from frontmatter. No validation needed — we trust the value that's already there.

**If user provides a date:**
Validate ISO 8601 format: `YYYY-MM-DDThh:mm:ss±HH:MM`

Valid examples:
- `2026-02-20T08:30:00-05:00`
- `2026-02-20T13:30:00-04:00`

**If format is invalid:**
- Show error: `Invalid date format. Expected ISO 8601: YYYY-MM-DDThh:mm:ss±HH:MM`
- Prompt again: `Publish date/time [default: {scheduled value}]:`
- Allow ONE retry
- If still invalid after retry: use the existing `scheduled` value and show: `Using default: {scheduled value}`

Store the validated publish date for Step 7.

### Step 7: Update Frontmatter

Update the frontmatter in the content file:

1. Set `status: approved` (change from `reviewed`)
2. Set or update `scheduled` field with the validated publish date from Step 6
3. Preserve ALL other frontmatter fields exactly as-is — do not add, remove, or modify any other fields

**Write the updated file back to the SAME location** (the file has not moved yet).

**Verify the write succeeded:**

Read the file back and confirm the `status` field now shows `approved`. If the read fails or status is not `approved`, output an error and STOP:

```
Error: Failed to update frontmatter for [piece_id]

The file may be locked or permissions may be incorrect.
Check: [file path]
```

### Step 8: Exemplar Candidate (Optional)

After moving the piece to ready/, prompt:

```
Add to exemplar library? [y/N]:
```

**If user enters `y` or `yes` (case-insensitive):**

1. Determine the route from frontmatter (`route` field). Map to exemplar file:
   - `linkedin` → `~/your-vault/03-Areas/professional-content/strategy/exemplars/linkedin.md`
   - `essay` or `substack-essay` → `~/your-vault/03-Areas/professional-content/strategy/exemplars/essay.md`
   - `twitter-thread` → `~/your-vault/03-Areas/professional-content/strategy/exemplars/twitter-thread.md`

2. Read the route exemplar file.

3. Count existing exemplars (## headings, excluding the top-level # heading).

4. If count >= 5 (or >= 3 for essays):
   - List existing exemplar titles with numbers
   - Prompt: `Library full. Replace which? [1-N/skip]:`
   - If user enters a number: replace that entry
   - If user enters `skip`: skip, proceed to Step 9

5. Prompt: `Why did this piece work? (1 sentence):`
   - Read the user's response

6. Identify the hook pattern used in the piece (contrarian reframe, narrative scene-setting, data-led, vulnerability, reactive commentary, etc.)

7. Append (or replace) the entry in the exemplar file with:
   ```markdown
   ---

   ## [Title from frontmatter] ([date])
   - **Hook pattern:** [identified pattern]
   - **Why it worked:** [user's sentence]

   [Full content body from the approved file]
   ```

8. Update the `updated:` date in the exemplar file's YAML frontmatter to today's date.

**If user enters anything else:** skip, proceed to Step 9.

### Step 9: Display Result

**Note:** Files never move. The approve action = write `status: approved` to frontmatter and stop.

Format the scheduled date for human-readable output:
- Parse the ISO 8601 datetime from the `scheduled` field
- Format as: `YYYY-MM-DD HH:MM TZ` (e.g., `2026-02-20 08:30 EST`)

Output:
```
Approved for publishing.

File: [file path]
Scheduled: [formatted date — YYYY-MM-DD HH:MM TZ]
Status: approved

Next: Publish manually at scheduled time, then update status to 'published'.
```

---

## Files

- **All content:** `~/your-vault/content/**/*.md`

## Anti-Patterns — Do NOT

- Auto-approve without user confirmation. The whole point of Gate 2 is human judgment.
- Move files. Files never move. Status lives in frontmatter only.
- Approve pieces with `revise` or `escalate` review decisions. Only `pass` decisions can advance.
- Invoke any agent. This is a human-only skill.
- Modify the content body (except for optional rejection feedback HTML comment).
- Write to SPRINT.md. That's /gcd:status domain.
