---
name: seed-idea
description: Capture a manual content idea as a brief stub in briefs/, compatible with /write-from-signal. Also serves as the weekly content queue viewer. Use when the user says "/seed-idea" to log an ad-hoc content idea or review the content pipeline.
license: MIT
origin: custom
author: Your Name
author_url: https://github.com/thatrebeccarae
---

# Seed Idea

Quick-capture a content idea into the brief pipeline, or view the weekly content queue.

## How to Use

```
/seed-idea [title]                # Create a brief stub for a manual idea
/seed-idea                        # Show the weekly content queue
/seed-idea --list                 # Show the weekly content queue (explicit)
```

## Behavior

### Mode 1: Create a Brief Stub (title provided)

When the user provides a title (e.g., `/seed-idea The Wrapper Problem`):

1. **Ask the user to describe the idea** — Just ask: "What's the idea?" Let them explain in their own words (1-3 sentences is fine).

2. **Infer pillar, route, and description from what they said:**
   - **Pillar** — Match to the best fit from: Pillar One / Pillar Two / Career & Leadership / Pillar Four. Use the Pillar-to-Day Mapping below.
   - **Route** — Determine from the idea's scope and depth:
     - `essay` — Deep analysis, contrarian take, multi-section argument (Substack long-form)
     - `linkedin` — Professional insight, quick take, conversation starter
     - `twitter-thread` — Punchy observations, listicle-style, hot take
   - **Description** — Synthesize their explanation into a clean 1-3 sentence angle for the brief
   - **Source file** — If they mention existing research or a vault note, link it

3. **Confirm with the user** — Present your inferences and ask for confirmation before creating:
   > **The Wrapper Problem**
   > Pillar: Pillar Two (Tuesday)
   > Route: essay
   > Idea: [your synthesized description]
   > Source: [linked file or "none"]
   >
   > Create this brief?

   The user can correct any field before you write the file. Only use AskUserQuestion if the idea is genuinely ambiguous between pillars or routes.

2. **Create the brief stub** at:
   ```
   ~/your-vault/briefs/YYYY-MM-DD-[slug].md
   ```

   Where `[slug]` is the kebab-case version of the title.

3. **Brief stub format** (manual ideas):

```yaml
---
signal_date: YYYY-MM-DD
topic: [slug]
source: manual
pillar: "[Pillar Name]"
route: [essay|linkedin|twitter-thread]
status: stub
research_source: [optional vault-relative path to source material]
---

# Content Brief: [Title]

## Idea

[User's description of the idea/angle]

## Source Material

- [[path/to/source|Display Name]] (if research_source provided)
- (none — original idea) (if no source)

## Content Recommendation

- **Type:** [Essay (Substack) | LinkedIn post + Twitter | Twitter thread]
- **Route:** `[route]`
- **Pillar:** [Pillar Name] ([Day])
- **Agent Chain:** [chain based on route — see below]

## Platform Constraints

[Auto-filled based on route — see Platform Constraints Reference below]

## Usage

Run in Claude Code:
\```
/write-from-signal [slug]
\```
```

4. **Confirm creation** — Show the user the file path and a `/write-from-signal [slug]` command they can use when ready.

### Mode 2: Weekly Content Queue (no title or --list)

When the user runs `/seed-idea` with no arguments or with `--list`:

1. **Scan sources:**
   - `~/your-vault/briefs/` — all `.md` files with `status: stub` in frontmatter
   - `~/your-vault/signals/story-seeds/story-seeds.md` — narrative threads and high-scoring seeds (8+)

2. **Classify by pillar** using these mappings:
   - **Pillar One** (Monday): pillar contains "AI", "Automation", "Pillar One", or story-seed pillar = "AI & Automation"
   - **Pillar Two** (Tuesday): pillar contains "E-Commerce", "Commerce", "Strategy", "Marketing Strategy", or story-seed pillar = "E-Commerce strategy"
   - **Career & Leadership** (Wednesday): pillar contains "Career", "Leadership"
   - **Pillar Four** (Thursday): pillar = "Pillar Four", or route = "essay" without another pillar match

   For pipeline briefs without a `pillar` field, infer from the topic and signal categories.

3. **Display format:**

```markdown
# Content Queue — Week of YYYY-MM-DD

## Monday: Pillar One
- [ ] MCP servers in enterprise (signal, 9/10 seed) — /write-from-signal mcp-enterprise
- [ ] Claude code access for non-technical teams (signal, 8/10 seed)

## Tuesday: Pillar Two
- [ ] **The Wrapper Problem** (manual, essay) — /write-from-signal the-wrapper-problem
- [ ] DTC retention — the second purchase (signal, 9/10 seed)

## Wednesday: Career & Leadership
- (no briefs queued)

## Thursday: Pillar Four
- [ ] [Any essay-route briefs land here]

---
X story seeds warming | Y narrative threads | Z pipeline briefs | W manual ideas
```

   Items with a brief stub get a `/write-from-signal` command. Story seeds without briefs are shown as informational (no command yet).

   Bold manual ideas to distinguish them from pipeline items.

## Reference Data

### Pillar-to-Day Mapping

| Day | Pillar |
|-----|--------|
| Monday | Pillar One |
| Tuesday | Pillar Two |
| Wednesday | Career & Leadership |
| Thursday | Pillar Four |

### Agent Chains by Route

| Route | Chain |
|-------|-------|
| `essay` | 1. research-analyst (opus) -> 2. content-marketer (sonnet) -> 3. editor-in-chief (opus) -> 4. social-amplifier (sonnet) |
| `linkedin` | 1. content-marketer (sonnet) -> 2. editor-in-chief (opus) -> 3. social-amplifier (sonnet) |
| `twitter-thread` | 1. content-marketer (sonnet) -> 2. social-amplifier (sonnet) |

### Platform Constraints Reference

**Essay (Substack):**
- Long-form (1500-3000 words)
- Structured with H2/H3 headers
- Personal voice with data backing
- End with takeaway or call to discussion

**LinkedIn:**
- 1300 char limit (optimal 800-1200)
- Hook in first 2 lines
- Line breaks for readability
- End with question or CTA
- 3-5 hashtags

**Twitter thread:**
- 280 char per tweet
- 4-8 tweets optimal
- Hook tweet + numbered insights + closer
- Each tweet standalone-readable

### Content Type Labels

| Route | Type Label |
|-------|-----------|
| `essay` | Essay (Substack) |
| `linkedin` | LinkedIn post + Twitter |
| `twitter-thread` | Twitter thread |

## Files

- **Briefs directory:** `~/your-vault/briefs/`
- **Story seeds:** `~/your-vault/signals/story-seeds/story-seeds.md`
- **Output location:** Same `briefs/` directory (manual briefs live alongside pipeline briefs)
