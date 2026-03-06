---
name: gcd-review
description: Run editorial review on a draft piece. Invokes gcd-reviewer agent, parses Decision (pass/revise/escalate), injects inline HTML comments, updates frontmatter. Use when user runs /gcd:review.
tools: Read, Write, Glob
---

# GCD Review

Editorial review gate (Gate 1) for GCD content pipeline. Invokes the gcd-reviewer agent, parses structured Decision output, injects inline HTML feedback comments into the draft, and updates frontmatter state.

Pass decisions advance pieces to `reviewed` status (ready for human Gate 2). Revise/escalate decisions keep pieces at `draft` status with inline feedback for iteration.

## How to Use

```
/gcd:review [piece-id]    # Review a draft piece (e.g., /gcd:review W08-01)
```

## Important Constraints

- Do NOT change `status` to anything other than `reviewed` (on pass) or leave as `draft` (on revise/escalate).
- Do NOT modify draft content beyond adding/removing HTML review comments.
- Do NOT invoke any agent other than gcd-reviewer.
- Do NOT approve pieces — that is /gcd:approve (Gate 2).
- Do NOT skip Step 4 (strip previous comments) — prevents duplicate comments on re-review.
- Do NOT write to SPRINT.md — that is /gcd:status domain.

---

## Behavior

Execute each step in order. Do not skip steps.

### Step 1: Parse Argument

Expect: `/gcd:review [piece-id]` (e.g., `/gcd:review W08-01`)

**If no argument provided:**
```
Error: No argument provided.
Usage: /gcd:review [piece-id]

Run /gcd:status to see current sprint pieces and their IDs.
```

Extract the `piece_id` string from the argument (e.g., `W08-01`).

### Step 2: Find the Draft

Glob ONE location to find the piece:

- `~/your-vault/content/**/*.md`

For each file returned from all four globs:
1. Read the full file content
2. Parse the YAML frontmatter (between the `---` delimiters)
3. Check if the `piece_id` field matches the provided argument (exact string match)

**If no match found:**
```
Error: No draft found with piece_id [arg].

Run /gcd:status to see current sprint pieces and their IDs.
```
STOP.

**If multiple matches found:**
```
Error: Multiple files found with piece_id [arg]. piece_id must be unique.
```
STOP.

**Store:**
- Draft file path (absolute path)
- Full file content (including frontmatter)
- All frontmatter fields: `status`, `piece_id`, `sprint`, `pillar`, `platform`, `title` (if present), and any others

### Step 3: Validate Status

Read the `status` field from the draft's frontmatter.

**If status is NOT `draft`:**

```
Error: Piece [piece_id] has status: [current status].
Only drafts can be reviewed. This piece is already past the draft stage.

Current status meanings:
- reviewed: passed Gate 1 (gcd-reviewer). Run /gcd:approve to promote to approved.
- approved: passed Gate 2 (human approval). Ready to publish.
- published: already live on platform.

If you want to re-review an approved or reviewed piece, change its status back to 'draft' first.
```
STOP.

**If status IS `draft`:** Continue to Step 4.

### Step 4: Strip Previous Review Comments

Before invoking the agent, strip ALL existing `<!-- REVIEW: ... -->` HTML comments from the draft content. This prevents duplicate comments on re-review.

**Pattern to remove:**
- Any line that starts with `<!-- REVIEW:` and ends with `-->`
- Match single-line comments: `<!-- REVIEW: [anything] -->`
- Match multi-line comments (rare, but possible):
  ```
  <!-- REVIEW: [anything]
  [more text]
  -->
  ```

**Process:**
1. Read the full file content (already loaded in Step 2)
2. Split content into frontmatter and body:
   - Frontmatter: everything between first `---` and second `---`
   - Body: everything after the second `---`
3. Remove all `<!-- REVIEW: ... -->` comment lines from the body (preserve frontmatter unchanged)
4. Write the cleaned file back (frontmatter + cleaned body)

**After writing:** Re-read the file to get the cleaned content for the agent invocation in Step 5.

### Step 5: Invoke Editor-in-Chief Agent

Pass the draft file path to the gcd-reviewer agent with this context:

```
Review this draft for Your Name's content pipeline.

Piece: {piece_id}
Sprint: {sprint}
Pillar: {pillar}
Platform: {platform from frontmatter}

Draft file: {absolute path to draft file}

Read the draft file and the voice guide at ~/your-vault/09-Profile/voice-guide.md, then produce your full editorial review following your output format.
```

**Agent invocation:** The gcd-reviewer agent will read the draft, evaluate it against the review framework, and return structured feedback.

**Store the complete agent output.** The next step parses this output.

### Step 6: Parse Decision

Extract the `Decision:` value from the Gate Evaluation block in the agent's output.

**Expected format in agent output:**
```markdown
## Gate Evaluation
- **Hook Grade:** [A/B/C/D]
- **Voice & Tone:** [Strong/Needs Work/Weak]
- **Structure:** [Strong/Needs Work/Weak]
- **Argument:** [Strong/Needs Work/Weak]
- **SEO:** [Strong/Needs Work/Weak]
- **Word Count:** [N]
- **Decision:** [pass/revise/escalate]

**Overall Assessment:** [text]
**Strongest Element:** [text]
**Priority Fix:** [text]
```

**Parsing process:**
1. Locate the line containing `**Decision:**` in the agent output
2. Extract the value after the colon (trim whitespace, convert to lowercase)
3. Match against: `pass`, `revise`, `escalate`

**If cannot parse Decision:**
```
Error: Could not parse Decision from review output.

Expected format: **Decision:** [pass/revise/escalate]

Check the gcd-reviewer agent output for the Gate Evaluation block.
```
STOP.

**Also extract for terminal display (Step 9):**
- Hook Grade
- Voice & Tone
- Structure
- Argument
- SEO
- Word Count
- Overall Assessment
- Strongest Element
- Priority Fix

Store all extracted values.

### Step 7: Inject HTML Comments

Parse the agent's "Detailed Feedback" and "Line-Level Notes" sections to generate inline HTML comments.

**Comment format:**
```html
<!-- REVIEW: [Category] - [Specific issue] -->
```

**Comment injection rules:**

1. **Extract feedback items** from these sections in the agent output:
   - "Detailed Feedback" subsections (Voice & Tone, Structure & Flow, Argument Quality, SEO & Discoverability, Readability)
   - "Line-Level Notes" (line/section references with specific feedback)

2. **Generate comments** for actionable feedback:
   - For each bullet point or note that describes a specific issue or improvement
   - Derive category from the subsection name (e.g., "Voice & Tone" → "Voice", "Structure & Flow" → "Structure")
   - Use the feedback text as the issue description

3. **Insert comments in the draft:**
   - Read the current draft file (cleaned in Step 4)
   - For each comment:
     - Identify the relevant section/paragraph in the draft
     - Insert the comment line BEFORE that section/paragraph
     - Never insert mid-sentence
   - If the Line-Level Note references a specific line or section (e.g., "Line 5:", "Hook:", "Section 2:"), insert before that location
   - If feedback is general (e.g., "Overall structure needs work"), insert at the top of the body (after frontmatter)

4. **Write updated file:**
   - Preserve ALL draft content exactly — only ADD comment lines
   - Maintain original line breaks and formatting
   - Comments should be on their own lines

**Example transformation:**

Original draft body:
```markdown
I've been building AI agents for six months.

The hardest part isn't the prompts or the tools. It's knowing when to stop.
```

After injection (if agent flagged the hook):
```markdown
<!-- REVIEW: Hook - Opening line is generic. Specific numbers/outcomes would strengthen. -->
I've been building AI agents for six months.

The hardest part isn't the prompts or the tools. It's knowing when to stop.
```

### Step 8: Update Frontmatter

Based on the parsed decision from Step 6, update the draft's frontmatter fields.

**Decision: pass**
- Set `status: reviewed`
- Set `review_decision: pass`

**Decision: revise**
- Keep `status: draft` (unchanged)
- Set `review_decision: revise`

**Decision: escalate**
- Keep `status: draft` (unchanged)
- Set `review_decision: escalate`

**Update process:**
1. Read the draft file (with injected comments from Step 7)
2. Parse frontmatter
3. Update ONLY `status` and `review_decision` fields
4. Preserve ALL other frontmatter fields exactly as-is (do not add, remove, or modify any other fields)
5. Write the updated file

**Frontmatter update rules:**
- If `review_decision` field does not exist, add it
- If `review_decision` field exists, overwrite it with the new decision value
- For `status`: update value or keep unchanged depending on decision (see above)

### Step 9: Display Terminal Summary

Show the user a structured summary of the review outcome.

**For decision: pass**

```
=== Editorial Review: [Title or piece_id] ===

Decision: PASS
Hook Grade: [grade]
Voice & Tone: [rating]
Structure: [rating]
Argument: [rating]
SEO: [rating]
Word Count: [N]

Overall: [assessment]
Strongest Element: [element]
Priority Fix: [fix]

Review complete. Piece advanced to 'reviewed' status.
Inline feedback added as HTML comments.

Next: Run /gcd:approve [piece_id] to promote to publish-ready.
```

**For decision: revise**

```
=== Editorial Review: [Title or piece_id] ===

Decision: REVISE
Hook Grade: [grade]
Voice & Tone: [rating]
Structure: [rating]
Argument: [rating]
SEO: [rating]
Word Count: [N]

Overall: [assessment]
Strongest Element: [element]
Priority Fix: [fix]

Piece remains in 'draft' status. Address inline feedback and re-run /gcd:review [piece_id].
```

**For decision: escalate**

```
=== Editorial Review: [Title or piece_id] ===

WARNING: Decision: ESCALATE — this needs your attention before any rewrite.
This signals judgment-level issues, not just mechanical fixes.

Hook Grade: [grade]
Voice & Tone: [rating]
Structure: [rating]
Argument: [rating]
SEO: [rating]
Word Count: [N]

Overall: [assessment]
Strongest Element: [element]
Priority Fix: [fix]

Piece remains in 'draft' status. Review inline comments carefully before proceeding.
Re-run /gcd:review [piece_id] after addressing concerns.
```

**Display note:** Use the `title` field from frontmatter if present (Substack essays). If `title` is absent (LinkedIn posts), use the `piece_id` instead.

---

## Files

- **All content:** `~/your-vault/content/**/*.md`
- **gcd-reviewer agent:** `~/.claude/agents/gcd-reviewer.md`
- **Voice guide:** `~/your-vault/09-Profile/voice-guide.md`

## Anti-Patterns — Do NOT

- Rewrite draft content. The skill only adds HTML comments, never modifies the author's text.
- Skip status validation. Only `draft` status pieces can be reviewed.
- Create a separate review file. All feedback lives as HTML comments in the draft itself.
- Treat escalate as a separate pipeline state. Escalate = revise + warning flag for the author to see judgment-level issues before attempting fixes.
- Inject comments mid-sentence. Always insert before sections/paragraphs.
- Skip Step 4 (strip previous comments). This causes duplicate comments on re-review.
- Proceed if the piece is already at `reviewed` or `approved` status. The review gate only applies to drafts.
