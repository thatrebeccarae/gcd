# GCD Frontmatter State Spec

**Version:** 1.0
**Created:** 2026-02-19
**Status:** Canonical reference for all GCD skills and agents

This document is the single reference for "what fields does a content piece have?" Every GCD skill, agent, and view reads from this spec. When in doubt, this document wins.

---

## 1. Existing Fields

These fields are already present in content files in the your-vault vault. They must be preserved exactly as-is — GCD does not rename, remove, or change the semantics of any existing field.

| Field | Type | Purpose | Used by |
|-------|------|---------|---------|
| `context` | string | Vault context (e.g., `professional`, `personal`) | linkedin, substack |
| `type` | string | Content format (e.g., `social`, `insight`) | linkedin, substack |
| `platform` | string | Target platform (e.g., `linkedin`, `substack`, `twitter`) | linkedin, substack |
| `status` | string | Lifecycle state — see Section 3 for valid values | linkedin, substack |
| `created` | date (YYYY-MM-DD) | Date the file was created | linkedin, substack |
| `title` | string | Article or post title | substack (essays) |
| `subtitle` | string | Article subtitle | substack (essays) |
| `slug` | string | URL-safe identifier (used in file path and URL) | substack (essays) |
| `tags` | list of strings | Categorical tags for filtering and discovery | linkedin, substack |
| `author` | string | Author name (e.g., `"Your Name"`) | substack (essays) |
| `description` | string | Short summary for meta/SEO | substack (essays) |
| `category` | string | Content category (e.g., `technology`, `marketing`) | substack (essays) |
| `date` | date (YYYY-MM-DD) | Publication or planned date | substack (essays) |
| `image` | string | Path or URL to featured image | substack (essays) |

**Rule:** `/gcd:status` and all GCD skills read these fields but never overwrite them unless the field is `status` (lifecycle transitions in Phases 3-4 update `status` only).

---

## 2. GCD-Specific Fields

These fields are NEW — added by GCD to content piece files. **ALL are optional** for backwards compatibility. A file without any GCD-specific fields is a pre-GCD file and is silently excluded from sprint views.

### `sprint`

- **Type:** string — ISO week identifier
- **Format:** `YYYY-WNN` (e.g., `"2026-W08"`)
- **Purpose:** Links the content piece to a specific sprint week. This is the primary filter field: `/gcd:status` filters by `sprint` field presence to scope sprint views.
- **Assigned by:** Sprint-planner skill (Phase 2) when a brief is selected for a sprint
- **Sprint week definition:** The week the content is *scheduled to publish*, not the week it was planned. A brief planned Sunday 2/15 for Monday 2/17 publish gets `sprint: 2026-W08`.
- **Absence means:** Pre-GCD file or unscheduled content — excluded from all sprint views

### `piece_id`

- **Type:** string — sprint-scoped piece identifier
- **Format:** `WNN-NN` (e.g., `"W08-01"`)
- **Purpose:** Unique identifier within a sprint. Used to reference a specific piece in SPRINT.md, retro files, and approval records.
- **Assigned by:** Sprint-planner skill (Phase 2) — not assigned in Phase 1
- **Absence means:** Piece is in sprint scope (has `sprint` field) but hasn't been through sprint planning yet, or this is a Phase 1 test file

### `pillar`

- **Type:** string — pillar name from `pillars.json`
- **Format:** Exact pillar name string (e.g., `"Pillar One"`, `"Pillar Four"`)
- **Purpose:** Maps the piece to one of the four strategy pillars. Drives coverage checks in `/gcd:status`.
- **Valid values:** Must match a `name` field in `pillars.json` — the four pillars are `"Pillar One"`, `"Pillar Two"`, `"Pillar Three"`, `"Pillar Four"`
- **Assigned by:** Sprint-planner skill (Phase 2) or content-marketer agent during drafting

### `scheduled`

- **Type:** string — ISO 8601 datetime with timezone
- **Format:** `YYYY-MM-DDThh:mm:ss±HH:MM` (e.g., `"2026-02-17T08:30:00-05:00"`)
- **Purpose:** When the piece is planned to publish. Used by `/gcd:status` to show slot assignments in the Pillar Coverage table.
- **Timezone:** Always include timezone offset. ET = `-05:00` (EST) or `-04:00` (EDT).
- **Assigned by:** Sprint-planner skill (Phase 2)

### `brief_slug`

- **Type:** string — slug matching a brief file in `01-Inbox/content-signals/briefs/`
- **Format:** kebab-case slug (e.g., `"building-practical-agents-with-claude-code"`)
- **Purpose:** Traceability — links the content piece back to the signal brief that originated it. Enables audit trail from signal → brief → piece → published.
- **Assigned by:** Sprint-planner skill (Phase 2) when brief is selected for sprint

### `review_decision`

- **Type:** string — editor-in-chief gate output
- **Valid values:** `pass`, `revise`, `escalate`
- **Purpose:** Records the outcome of Gate 1 (editor-in-chief review). Present only after a piece has been through `/gcd:review`. Drives status transition from `draft` → `reviewed` (on `pass`) or keeps at `draft` (on `revise`).
- **Assigned by:** `/gcd:review` skill (Phase 4) parsing the editor-in-chief agent's `Decision:` line
- **Absence means:** Piece has not been through Gate 1 yet

### `engagement_metrics`

- **Type:** object — nested platform-keyed engagement data
- **Format:** Platform name keys (e.g., `linkedin`, `twitter`, `substack`) each containing metrics object
- **Purpose:** Stores per-platform engagement data captured during sprint retrospective. Enables performance analysis by pillar, route, and topic in Phase 11.
- **Assigned by:** `/gcd:retro` skill (Phase 9) during engagement metric collection step
- **Absence means:** Metrics not yet captured (piece may not have been posted yet, or user skipped during retro)

**Structure:**

```yaml
engagement_metrics:
  platform_name:
    impressions: integer (>= 0)
    reactions: integer (>= 0)
    comments: integer (>= 0)
    shares: integer (>= 0)
    engagement_rate: float (calculated: (reactions + comments + shares) / impressions)
    collected_date: ISO 8601 datetime string
```

**Zero vs skip distinction:**
- User entered all zeros = platform key exists with all 0 values + collected_date (means "checked, zero engagement")
- User skipped = platform key does NOT exist (means "no data yet")

**Validation rules:**
- reactions, comments, shares each must be <= impressions (warn if violated, do not block)
- If impressions is 0, engagement_rate is 0.0 (avoid division by zero)

### `post_url`

- **Type:** string (URL)
- **Format:** `https://www.linkedin.com/feed/update/urn:li:activity:NNNN...`
- **Purpose:** Links piece to its published LinkedIn post. Enables auto-matching engagement metrics from `linkedin-metrics.jsonl`.
- **Assigned by:** `/gcd:retro` Step 6 (when user matches a piece to a LinkedIn post), or manually
- **Absence means:** Piece not yet linked to a published post

---

## 3. Lifecycle Status Values

The `status` field tracks where a content piece is in its production lifecycle. These are the valid values and their meaning.

| Status | Meaning |
|--------|---------|
| `stub` | Brief captured, not yet in sprint or being drafted. The brief file in `01-Inbox/content-signals/briefs/` has this status. |
| `draft` | In-progress drafting. The piece has been assigned to a sprint, a content file exists, and content is being written. |
| `reviewed` | Editor-in-chief Gate 1 passed (`review_decision: pass`). Piece is ready for human review. |
| `approved` | Human approved via `/gcd:approve` (Gate 2). The piece is publish-ready. No further changes needed. |
| `published` | Live on platform. Piece has been posted to LinkedIn, Substack, or other platform. |
| `measured` | Engagement metrics captured in sprint retro. Terminal state. |
| `cancelled` | Deliberately abandoned — topic no longer viable or relevant. Terminal state. Piece is archived and excluded from sprint views and queue. |

**Lifecycle order (forward direction):**

```
stub → draft → reviewed → approved → published → measured
                    ↑          |
                    └──────────┘  (revise loop: reviewed → draft on revise decision)

cancelled ← (any non-terminal state — deliberate abandonment)
```

**Note:** Cancelled is a terminal state like measured. Any piece at stub, draft, or reviewed status can be cancelled. Approved, published, and measured pieces cannot be cancelled (they have already cleared gates). Cancelled pieces have their sprint fields cleared and do not appear in /gcd:queue or /gcd:status active views.

**Phase 1 boundary:** This spec defines the state values and their meaning only. Transition rules — what triggers a state change, who is authorized to make transitions, and how the revise loop is handled — are Phase 3-4 concerns. Phase 1 only reads and displays current state.

**Pre-GCD status values:** Existing files may have `status: published` or `status: draft` without any GCD-specific fields. These values are compatible — they are on the same status scale. `/gcd:status` does not error on these files; it simply excludes them from sprint views because they lack the `sprint` field.

---

## 4. Backwards Compatibility

**Rule:** Files without GCD-specific fields are silently excluded from sprint views. No migration needed for existing content files.

**How this works in practice:**

- `/gcd:status` scans vault content directories with Glob
- For each file, it reads frontmatter and checks for the `sprint` field
- If `sprint` is absent, the file is skipped — no error, no warning, no output
- If `sprint` is present, the file is included in the sprint view

**This means:**

- All existing LinkedIn posts, Substack essays, and brief stubs continue to work exactly as before
- No backfill migration is needed — GCD only tracks pieces that have been through sprint planning
- The gap between "files that exist" and "files in a sprint" is intentional — not all content is sprint-produced

**Migration policy:** Do not migrate existing files. If an existing published piece needs to be brought into GCD tracking (e.g., for retro comparison), it is a deliberate act with explicit frontmatter additions — not an automatic migration.

---

## 5. Complete Examples

### Example 1: LinkedIn Post with All GCD Fields

```yaml
---
context: professional
type: social
platform: linkedin
pillar: "Pillar One"
sprint: "2026-W08"
piece_id: "W08-01"
status: draft
created: 2026-02-17
scheduled: "2026-02-17T08:30:00-05:00"
brief_slug: "building-practical-agents-with-claude-code"
tags: [claude-code, ai, linkedin, automation]
---
```

This is a LinkedIn post assigned to the Monday "Pillar One" slot in sprint W08. It is currently being drafted. It has been linked to its originating brief. `review_decision` is absent because it has not yet been through Gate 1.

### Example 2: Substack Essay with All GCD Fields

```yaml
---
context: professional
type: insight
platform: substack
pillar: "Pillar Four"
sprint: "2026-W08"
piece_id: "W08-04"
status: reviewed
title: "The Wrapper Problem"
subtitle: "When AI commoditizes the interface layer"
slug: the-wrapper-problem
author: "Your Name"
description: "On the collapse of the 'thin wrapper on GPT-4' product category and what it means for technical differentiation."
created: 2026-02-20
scheduled: "2026-02-20T09:00:00-05:00"
brief_slug: "the-wrapper-problem"
review_decision: pass
tags: [ai, strategy, substack, essays]
image: ""
---
```

This is a Substack essay assigned to the Thursday "Pillar Four" slot in sprint W08. It has passed Gate 1 (`review_decision: pass`) and is at `reviewed` status, waiting for human approval via `/gcd:approve`.

### Example 3: Measured LinkedIn Post with Engagement Metrics

```yaml
---
context: professional
type: social
platform: linkedin
pillar: "Pillar One"
sprint: "2026-W08"
piece_id: "W08-01"
status: measured
created: 2026-02-17
scheduled: "2026-02-17T08:30:00-05:00"
brief_slug: "building-practical-agents-with-claude-code"
review_decision: pass
tags: [claude-code, ai, linkedin, automation]
engagement_metrics:
  linkedin:
    impressions: 1250
    reactions: 45
    comments: 8
    shares: 3
    engagement_rate: 0.0448
    collected_date: "2026-02-23T10:30:00-05:00"
---
```

This is a LinkedIn post that has been published and measured. Engagement metrics were collected during `/gcd:retro` with a 4.48% engagement rate. The `measured` status is the terminal success state indicating metrics have been captured.
