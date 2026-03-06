# Write From Signal - Reference

## Implementation Details

### Step 1: Find and Parse Brief

```
BRIEFS_DIR = ~/your-vault/briefs/
TODAY = YYYY-MM-DD (today's date)
YESTERDAY = YYYY-MM-DD (yesterday's date)
```

1. Use Glob to find `{BRIEFS_DIR}/{TODAY}-*.md`
2. If none found, try `{BRIEFS_DIR}/{YESTERDAY}-*.md`
3. If still none, read most recent `~/your-vault/signals/*-signals.md` and suggest `/research-digest [topic]` for any interesting signals
4. Parse YAML frontmatter from matched brief(s) to extract: `topic`, `impact_score`, `route`, `content_type`, `status`

### Step 2: Topic Matching

If user provides a topic argument:
- Normalize: lowercase, strip punctuation
- Match against brief filenames (slug portion) and frontmatter `topic` field
- Use substring matching (e.g., "ai agents" matches "ai-agents-autonomous-workflows")
- If multiple matches, show options and ask user to pick
- If no match, list all available briefs

If no topic argument:
- List all briefs with: topic, impact score, route, status
- Ask user to pick one

### Step 3: Status Update on Start

Read the matched brief file. Replace `status: stub` with `status: in-progress` in the frontmatter. Write the file back.

### Step 4: Execute Route

Read the full brief content to pass to the first agent.

#### Route: `essay`

**Stage 1 - Research:**
```
Spawn: research-analyst agent (model: opus)
Input: Brief content passed inline + key article URLs from the brief
Task: "Research this topic for a Substack essay. The signal brief is below.
       Read the key articles, synthesize findings, identify the unique angle.
       Save your research brief to ~/your-vault/01-Inbox/research-briefs/YYYY-MM-DD-[slug].md"
Output: research brief file path
```
-> Show user the research brief location. Ask: continue / feedback / stop.

**Stage 2 - Draft:**
```
Spawn: content-marketer agent (model: sonnet)
Input: File paths to research brief + signal brief
Task: "Write a Substack newsletter essay (1500-3000 words) based on:
       1. Research brief at [path]
       2. Signal brief at [path]
       Follow the brand voice guide if available.
       Save to ~/your-vault/03-Areas/professional-content/articles/drafts/[slug]/article.md"
Output: draft file path
```
-> Show user the draft location. Ask: continue / feedback / stop.

**Stage 3 - Review:**
```
Spawn: editor-in-chief agent (model: opus)
Input: Draft file path
Task: "Review this article draft at [path].
       Evaluate: voice consistency, argument structure, SEO, readability.
       Save revision notes to [same directory]/revision-notes.md"
Output: revision notes file path
```
-> Show user the review notes location. Ask: continue / feedback / stop.

**Stage 4 - Social:**
```
Spawn: social-amplifier agent (model: sonnet)
Input: Draft file path
Task: "Create a social distribution pack for the article at [path].
       Generate: LinkedIn post (2 variants), Twitter/X thread, email subject lines.
       Save to [same directory]/social/"
Output: social pack directory
```
-> Show user the social pack location.

#### Route: `linkedin`

**Stage 1 - Draft:**
```
Spawn: content-marketer agent (model: sonnet)
Input: Brief content inline + key article URLs
Task: "Write a LinkedIn post based on this signal brief.
       Constraints: 800-1300 chars, hook in first 2 lines, end with question/CTA, 3-5 hashtags.
       Save to ~/your-vault/03-Areas/professional-content/standalone/linkedin/YYYY-MM-DD-[slug].md"
Output: post file path
```
-> Show user. Ask: continue / feedback / stop.

**Stage 2 - Review:**
```
Spawn: editor-in-chief agent (model: opus)
Input: Post file path
Task: "Review this LinkedIn post at [path].
       Focus on: hook strength, readability, CTA clarity, hashtag relevance.
       Save review notes alongside the post."
Output: review notes path
```
-> Show user. Ask: continue / feedback / stop.

**Stage 3 - Social:**
```
Spawn: social-amplifier agent (model: sonnet)
Input: Post file path
Task: "Create cross-platform variants for the LinkedIn post at [path].
       Generate: Twitter/X thread version, email subject lines.
       Save alongside the post."
Output: social variants path
```

#### Route: `twitter-thread`

**Stage 1 - Draft:**
```
Spawn: content-marketer agent (model: sonnet)
Input: Brief content inline + key article URLs
Task: "Write a Twitter/X thread based on this signal brief.
       Constraints: 280 chars per tweet, 3-8 tweets, hook tweet stands alone, 1-2 links, end with CTA.
       Save to ~/your-vault/03-Areas/professional-content/standalone/twitter/YYYY-MM-DD-[slug].md"
Output: thread file path
```
-> Show user. Ask: continue / feedback / stop.

**Stage 2 - Social:**
```
Spawn: social-amplifier agent (model: sonnet)
Input: Thread file path
Task: "Create a LinkedIn cross-post variant for the Twitter thread at [path].
       Save alongside the thread."
Output: cross-post path
```

### Step 5: Final Status Update

After the user confirms the last stage is complete, update the brief frontmatter:
- Replace `status: in-progress` with `status: published`

## File Paths Summary

| Content Type | Draft Location |
|-------------|---------------|
| Essay | `~/your-vault/03-Areas/professional-content/articles/drafts/[slug]/article.md` |
| LinkedIn | `~/your-vault/03-Areas/professional-content/standalone/linkedin/YYYY-MM-DD-[slug].md` |
| Twitter | `~/your-vault/03-Areas/professional-content/standalone/twitter/YYYY-MM-DD-[slug].md` |
| Research | `~/your-vault/01-Inbox/research-briefs/YYYY-MM-DD-[slug].md` |
| Briefs | `~/your-vault/briefs/YYYY-MM-DD-[slug].md` |

## Agent Configuration

| Agent | Available As | Has Read Tool | Has Write Tool |
|-------|-------------|---------------|----------------|
| research-analyst | `~/.claude/agents/research-analyst.md` | Yes | Yes |
| content-marketer | `~/.claude/agents/content-marketer.md` | Yes | Yes |
| editor-in-chief | `~/.claude/agents/editor-in-chief.md` | Yes | Yes |
| social-amplifier | `~/.claude/agents/social-amplifier.md` | Yes | Yes |

## Error Handling

- If an agent fails, show the error and ask user how to proceed
- Never skip stages silently
- If brief has `status: published`, warn user and ask if they want to re-run
- If brief has `status: in-progress`, offer to resume from where it left off

## Slug Generation

From topic string:
1. Lowercase
2. Replace non-alphanumeric with hyphens
3. Collapse multiple hyphens
4. Trim leading/trailing hyphens
5. Truncate to 50 chars

Example: "AI Agents + Autonomous Workflows" -> `ai-agents-autonomous-workflows`
