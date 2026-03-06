---
name: gcd-reject
description: Reject a pipeline draft entirely. Marks content file as rejected, brief as skipped, preserves .draft.md for anti-pattern learning. Use when user runs /gcd:reject.
tools: Read, Write, Bash, Glob, Grep
---

# GCD Reject

Kill a pipeline draft that isn't worth revising. This is different from rejection-with-feedback in `/gcd:approve` — this is "throw it away, I'm writing something else or skipping this topic entirely."

## How to Use

```
/gcd:reject [piece-id]     # Reject a draft entirely (e.g., /gcd:reject W10-01)
```

Run `/gcd:status` to see piece IDs and their current status.

## Important Constraints

- Do NOT invoke any agent — this is a human-only action.
- Do NOT delete any files — the `.draft.md` stays for anti-pattern learning.
- Do NOT move files — status lives in frontmatter only.
- The `.draft.md` sibling is preserved as a negative signal for voice learning.

---

## Behavior

Execute each step in order. Do not skip steps.

### Step 1: Parse Argument

Expect: `/gcd:reject [piece-id]` (e.g., `/gcd:reject W10-01`)

**If no argument provided:**
```
Error: No argument provided.
Usage: /gcd:reject [piece-id]

Run /gcd:status to see current sprint pieces and their IDs.
```
STOP.

Extract the `piece_id` string from the argument.

### Step 2: Find the Draft

Glob content directory:
- `~/your-vault/content/**/*.md`

Exclude `.draft.md` files from results.

For each file returned:
1. Read the full file content
2. Parse the YAML frontmatter (between the `---` delimiters)
3. Check if the `piece_id` field matches the provided argument (exact string match)

**If no match found:** Output error and STOP.
**If multiple matches found:** Output error and STOP.

**Store:**
- File path (absolute path to the content file)
- All frontmatter fields
- The brief_slug field (to find the corresponding brief)

### Step 3: Validate Status

Read the `status` field from the frontmatter.

**Valid statuses for rejection:** `draft`, `reviewed`

A piece can be rejected if it's a fresh draft or if it passed review but the human still doesn't want it.

**If status is `approved` or `published` or `measured`:**
```
ERROR: Cannot reject piece [piece_id]

Current status: [status]

This piece has already been approved/published. Rejection is only for drafts and reviewed pieces that haven't been published yet.
```
STOP.

**If status is already `rejected`:**
```
Piece [piece_id] is already rejected.
```
STOP.

### Step 4: Confirm Rejection

Display:
```
=== Reject Draft ===

Piece: [piece_id] ([title from frontmatter])
Sprint: [sprint]
Status: [current status]
Brief: [brief_slug]

This will:
- Mark the content file as 'rejected'
- Mark the brief as 'skipped'
- Preserve the .draft.md for anti-pattern learning

Reject this draft? [y/N]:
```

Wait for user input.

**If user enters anything other than `y` or `yes`:**
```
Rejection cancelled.
```
STOP.

### Step 5: Optional Reason

Prompt:
```
Reason for rejection (optional — helps voice learning):
```

Read the user's input. If empty, that's fine — proceed without a reason.

### Step 6: Update Content File

Update the frontmatter in the content file:

1. Set `status: rejected`
2. Add `rejected_date: [today's date YYYY-MM-DD]`
3. If a reason was provided, add `rejection_reason: "[reason]"`
4. Preserve ALL other frontmatter fields exactly as-is

Write the updated file back to the same location.

### Step 7: Update Brief

Find the corresponding brief file using the `brief_slug` from frontmatter:
- `~/your-vault/briefs/[brief_slug].md`

If the brief file exists:
1. Change `status: draft` (or `status: stub`) to `status: skipped`
2. Add `skipped_date: [today's date YYYY-MM-DD]`
3. If a reason was provided, add `skip_reason: "[reason]"`

If the brief file doesn't exist, log a warning but don't fail.

### Step 8: Verify .draft.md Exists

Check if the `.draft.md` sibling exists:
- `[same path as content file but with .draft.md extension]`

**If it exists:** Good — it will be picked up by `voice-diff-analysis.sh` for anti-pattern learning.

**If it doesn't exist:** Warn the user:
```
Note: No .draft.md snapshot found for this piece. Anti-pattern learning won't have the original GCD output to analyze.
```

### Step 9: Display Result

```
Rejected.

Content: [file path] (status: rejected)
Brief: [brief path] (status: skipped)
Draft snapshot: [.draft.md path] (preserved for anti-pattern learning)

The voice learning system will analyze this rejected draft to improve future output.
```

---

## Files

- **Content:** `~/your-vault/content/**/*.md`
- **Briefs:** `~/your-vault/briefs/*.md`

## Anti-Patterns -- Do NOT

- Delete the content file or the `.draft.md` — both are valuable data.
- Auto-reject without user confirmation.
- Move files. Status lives in frontmatter only.
- Invoke any agent. This is a human-only skill.
