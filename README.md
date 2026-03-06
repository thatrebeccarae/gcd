<div align="center">

# Get Content Done

**Sprint planning, two-gate quality, and performance feedback loops for content — powered by Claude Code skills.**

[![Claude Code](https://img.shields.io/badge/Claude_Code-Skills-cc785c?style=for-the-badge&logo=anthropic&logoColor=white)](https://docs.anthropic.com/en/docs/claude-code)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-Rebecca%20Rae%20Barton-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://linkedin.com/in/rebeccaraebarton)
[![X](https://img.shields.io/badge/X-@rebeccarae-000000?style=for-the-badge&logo=x&logoColor=white)](https://x.com/rebeccarae)
[![GitHub stars](https://img.shields.io/github/stars/thatrebeccarae/gcd?style=for-the-badge&logo=github&color=181717)](https://github.com/thatrebeccarae/gcd/stargazers)
[![License](https://img.shields.io/badge/License-MIT-0A66C2?style=for-the-badge)](LICENSE)
[![Clone](https://img.shields.io/badge/Clone-git%20clone-f78166?style=for-the-badge&logo=git&logoColor=white)](https://github.com/thatrebeccarae/gcd)

<br>

```bash
git clone https://github.com/thatrebeccarae/gcd.git
```

<br>
<br>

[What It Does](#what-it-does) · [Skills](#skills) · [Agents](#agents) · [How It Works](#how-it-works) · [Getting Started](#getting-started) · [Extending GCD](#extending-gcd) · [Credits](#credits)

</div>

---

## What It Does

GCD applies sprint methodology to content production. You define your content pillars, feed in signal briefs, and run a weekly cycle: **plan → produce → review → approve → retro**. Each step is a Claude Code slash command. Each piece of content tracks its own state in YAML frontmatter. Nothing moves directories. Nothing slips through the cracks.

```
┌─────────────────────────────────────────────────────┐
│  SKILLS + AGENTS      Sprint planning, drafting,    │
│                       review gates, retrospectives  │
├─────────────────────────────────────────────────────┤
│  STATE LAYER          YAML frontmatter, pillars     │
│                       config, brief queue           │
└─────────────────────────────────────────────────────┘
```

**State layer** — `pillars.json` defines your content pillars, posting schedule, and quality gates. YAML frontmatter on every content file tracks lifecycle status. Files never move; status lives in frontmatter only.

**Skills + agents** — 10 Claude Code skills orchestrate the workflow. 7 specialized agents handle scoring, drafting, review, research, and analytics. You interact through slash commands; agents do the heavy lifting behind each one.

## Skills

| Skill | Function |
|-------|----------|
| `/gcd:status` | Sprint dashboard — pieces, pillar coverage, velocity trends, bottleneck detection |
| `/gcd:queue` | Signal brief queue with composite scoring and pillar-fit suggestions |
| `/gcd:plan-sprint` | Interactive sprint planning with agent-scored recommendations and pillar enforcement |
| `/gcd:produce` | Route-dispatched content drafting (LinkedIn, Substack essay, Twitter/X thread, newsletter) |
| `/gcd:review` | Editorial review gate — agent-powered quality check (Gate 1) |
| `/gcd:approve` | Human approval gate (Gate 2) |
| `/gcd:reject` | Reject a draft with feedback — preserves `.draft.md` for anti-pattern learning |
| `/gcd:retro` | Sprint close with pipeline metrics, engagement analysis, and performance feedback loop |
| `/seed-idea` | Capture a manual content idea as a brief stub |
| `/write-from-signal` | Convert a signal brief into a finished draft via the appropriate agent chain |

## Agents

| Agent | Role |
|-------|------|
| `gcd-sprint-planner` | Scores briefs against pillars using composite formula (keyword 50% + pillar fit 30% + route fit 20%), detects strategy drift, applies performance boosts from historical data |
| `gcd-producer` | Drafts content by route — LinkedIn posts, Substack essays, Twitter threads, newsletter sections. Reads voice guide before every piece. |
| `gcd-reviewer` | Editorial review (Gate 1) — checks voice consistency, structure, hook quality (A/B/C/D grading), SEO criteria, readability. Returns pass/revise/escalate. |
| `gcd-researcher` | Topic research for essay route — consumes RSS feeds and web sources, produces structured research briefs with data points, counter-arguments, and content angles |
| `gcd-amplifier` | Cross-platform distribution — generates LinkedIn posts, Twitter threads, email subject lines, and pull quotes from finished content |
| `gcd-metrics-analyst` | Pipeline analytics — throughput rates, gate performance, route comparison, high/low performer identification |
| `gcd-strategy-auditor` | Strategy health — rolling-window pillar drift detection, 3-sprint velocity trends, pipeline bottleneck identification |

## How It Works

### Content Lifecycle

YAML frontmatter is the single source of truth. Each piece moves through a defined lifecycle:

```
stub → draft → reviewed → approved → published → measured
                   ↑          |
                   └──────────┘  (revise loop)

              draft/reviewed → rejected  (terminal, preserved for learning)
```

### Sprint Planning

The `gcd-sprint-planner` agent scores signal briefs using a composite formula: keyword match (50%) + pillar fit with underrepresentation boost (30%) + route fit (20%). Historical performance data applies boosts to high-performing route+pillar combinations (+0.1) and gentle penalties to underperformers (-0.05). A 4-week rolling window detects pillar drift — if you haven't posted about a topic in two weeks, the planner surfaces it without hard-blocking.

### Route-Dispatched Drafting

`/gcd:produce` routes each brief to the right agent workflow:
- **LinkedIn post** — direct to `gcd-producer` with voice guide
- **Substack essay** — research phase via `gcd-researcher`, then draft via `gcd-producer`
- **Twitter/X thread** — threaded format with character-aware splitting
- **Newsletter** — section assembly from approved pieces

### Two-Gate Quality

**Gate 1 (Agent):** The `gcd-reviewer` catches what machines catch well — style consistency, structural issues, hook quality grading (A/B/C/D), SEO criteria, suggested title variants. Returns pass, revise, or escalate.

**Gate 2 (Human):** `/gcd:approve` catches what humans catch well — tone, judgment, relevance, "does this actually sound like me?" Neither gate alone is enough. Both together cover the full surface.

### Performance Feedback Loop

`/gcd:retro` closes the sprint with pipeline metrics and engagement analysis. The `gcd-metrics-analyst` identifies high and low performers by route and pillar. This data feeds back into the sprint planner — next week's scoring boosts what worked and nudges away from what didn't.

<details>
<summary><strong>Composite scoring formula</strong></summary>

The sprint planner scores each brief against each pillar:

```
composite = keyword_normalized * 0.5 + pillar_fit * 0.3 + route_fit * 0.2
```

Where:
- **keyword_normalized** (0.0-1.0): How many pillar keywords appear in the brief topic, divided by total keywords
- **pillar_fit** (0.0-1.0): keyword_normalized + underrepresentation boost (up to +0.3 for neglected pillars) + performance boost (+0.1/-0.05 from historical data)
- **route_fit** (0.0 or 1.0): Whether the brief's route matches the pillar's content types

Visual indicators in queue view:
- Score >= 0.6: strong signal
- Score 0.4-0.59: borderline
- Score < 0.4: weak signal

</details>

<details>
<summary><strong>Pillar enforcement and rolling windows</strong></summary>

The `pillars.json` config defines your content pillars with target posting frequencies. During sprint planning, the agent checks a 4-week rolling window of published content to calculate pillar coverage. If a pillar is underrepresented, the planner surfaces it as a suggestion — not a blocker. This keeps the system opinionated but flexible.

The enforcement config controls this behavior:
- `window_weeks`: How many weeks to look back (default: 4)
- `flag_missing_after_weeks`: When to start warning about a missing pillar (default: 2)
- `hard_block`: Whether to prevent sprint confirmation when a pillar is missing (default: false)

</details>

<details>
<summary><strong>Content state and frontmatter</strong></summary>

Every content file uses YAML frontmatter to track its current state. Files never move directories — status lives entirely in frontmatter. This means you can query your vault with Dataview, grep, or any tool that reads YAML to get a real-time view of your pipeline.

GCD adds these fields to your existing frontmatter (all optional for backwards compatibility):
- `sprint` — ISO week identifier (e.g., `2026-W08`)
- `piece_id` — Sprint-scoped ID (e.g., `W08-01`)
- `pillar` — Strategy pillar name from `pillars.json`
- `scheduled` — ISO 8601 datetime with timezone
- `brief_slug` — Links back to the originating signal brief
- `review_decision` — Gate 1 output (pass/revise/escalate)
- `engagement_metrics` — Nested platform-keyed metrics object
- `post_url` — Link to published post for metrics matching

See [`frontmatter-spec.md`](.planning/schemas/frontmatter-spec.md) for the complete specification.

</details>

## Getting Started

**Prerequisites:**

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI installed and configured
- A markdown-based content store (Obsidian vault, flat files, whatever works)

**Install:**

```bash
# Clone the repo
git clone https://github.com/thatrebeccarae/gcd.git

# Copy skills to your Claude Code skills directory
cp -r gcd/skills/* ~/.claude/skills/

# Copy agents to your Claude Code agents directory
cp -r gcd/agents/* ~/.claude/agents/
```

**Configure:**

1. Copy `pillars.example.json` to your repo as `pillars.json`
2. Edit pillar names, posting days, keywords, and content types to match your strategy
3. Update vault paths in skill files to point to your content directories
4. Add signal briefs to your vault's inbox (manually via `/seed-idea` or from any source)
5. Run `/gcd:plan-sprint` to kick off your first sprint

<details>
<summary><strong>Path configuration</strong></summary>

Skills and agents reference three path categories that you'll need to update:

| Path | Default | What it points to |
|------|---------|-------------------|
| Repo path | `~/your-repo/` | Where you cloned GCD (for `pillars.json`, schemas, retros) |
| Content path | `~/your-vault/content/` | Where your content files live |
| Brief path | `~/your-vault/briefs/` | Where signal briefs are stored |

Search for these paths in the skill and agent `.md` files and replace with your actual paths.

</details>

## Extending GCD

GCD is the skill + agent + state layer. What feeds it — and what you do after `/gcd:approve` — is up to you.

Some things that pair well:
- **RSS scanning** for automated signal brief generation (Miniflux, Feedly, any reader with an API)
- **Scheduled pipelines** that run the brief queue before you wake up (cron, LaunchAgent, n8n, whatever)
- **Voice drift analysis** comparing AI drafts (`.draft.md`) against your published edits to build a living style guide
- **Engagement metrics sync** from platform data exports to close the feedback loop in `/gcd:retro`

None of these are required. GCD works with manual brief capture (`/seed-idea`) and manual metrics entry.

## Credits

GCD was directly inspired by [Get Shit Done (GSD)](https://github.com/gsd-build/get-shit-done), which applies sprint methodology and Claude Code skills to software engineering projects. GSD proved that skills + agents + structured state could replace heavyweight project management for solo builders. GCD takes the same philosophy — plan, execute, verify, retro — and adapts it for content production workflows.

## Contributing

Issues and PRs welcome. If you're adapting GCD for a different content workflow, I'd genuinely like to hear about it.

An active project and open-sourced as-is. Use it, adapt it, break it apart for pieces.

## License

[MIT](LICENSE)
