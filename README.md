<div align="center">

# Get Content Done

**GCD — a skill-based content production framework for Claude Code.**

Sprint planning. Autonomous drafting. Two-gate quality. Full automation stack.

[![GitHub stars](https://img.shields.io/github/stars/thatrebeccarae/gcd?style=for-the-badge&logo=github&color=181717)](https://github.com/thatrebeccarae/gcd/stargazers)
[![License](https://img.shields.io/badge/License-MIT-0A66C2?style=for-the-badge)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude_Code-Skills-cc785c?style=for-the-badge&logo=anthropic&logoColor=white)](https://docs.anthropic.com/en/docs/claude-code)

```bash
git clone https://github.com/thatrebeccarae/gcd.git
```

[Why I Built This](#why-i-built-this) · [Who This Is For](#who-this-is-for) · [The Full Stack](#the-full-stack) · [Skills](#skills) · [Agents](#agents) · [Automations](#automations) · [Getting Started](#getting-started) · [How It Works](#how-it-works) · [License](#license)

</div>

---

## Why I Built This

Content production has a process problem. Every week I was staring at a pile of signal briefs, half-drafted LinkedIn posts, and a vague sense that I hadn't talked about one of my pillars in three weeks. The work itself wasn't hard — the orchestration was. Deciding what to write, in what order, against which pillar, and then actually pushing each piece through drafting, review, and approval before the week ran out.

Code projects solved this decades ago with sprint planning, CI gates, and retros. Content deserves the same rigor. GCD gives weekly content sprints a structured lifecycle — plan, produce, review, approve, retro — using Claude Code skills and specialized agents so I can focus on the writing instead of the bookkeeping.

Then I automated the inputs. RSS feeds get scanned daily for content signals. Briefs are auto-generated and scored. A morning pipeline runs before I wake up so the queue is ready when I sit down. Weekly retros analyze what performed and feed that data back into the next sprint's scoring. Voice drift is tracked by comparing AI drafts against my published edits.

The result is a system where YAML frontmatter is the single source of truth, every piece of content has a clear state, nothing slips through the cracks, and the system learns from what works.

## Who This Is For

- **Solo content operators** who publish on a regular cadence and want sprint-style structure without a project manager
- **Builder-marketers** already using Claude Code who want to extend it into content workflows
- **Anyone drowning in drafts** who needs a clear pipeline from signal to published post with quality gates along the way

## The Full Stack

GCD is three layers working together:

```
┌─────────────────────────────────────────────────────┐
│  AUTOMATIONS          Daily pipeline, retros,       │
│                       voice learning, metrics sync  │
├─────────────────────────────────────────────────────┤
│  SKILLS + AGENTS      Sprint planning, drafting,    │
│                       review gates, retrospectives  │
├─────────────────────────────────────────────────────┤
│  STATE LAYER          YAML frontmatter, pillars     │
│                       config, brief queue           │
└─────────────────────────────────────────────────────┘
```

**State layer** — `pillars.json` defines your content pillars, posting schedule, and quality gates. YAML frontmatter on every content file tracks lifecycle status. Files never move directories; status lives in frontmatter only.

**Skills + agents** — 10 Claude Code skills orchestrate the workflow. 7 specialized agents handle scoring, drafting, review, research, and analytics. You interact through slash commands; agents do the heavy lifting behind each one.

**Automations** — A morning pipeline, weekly retrospectives, voice drift analysis, and metrics sync run on schedule. The pipeline produces scored briefs before you wake up; retros analyze performance and feed insights back into sprint planning.

## Skills

| Skill | Function |
|-------|----------|
| `/gcd:status` | Sprint dashboard — pieces, pillar coverage, strategy drift, velocity trends, bottleneck detection |
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

## Automations

The automation layer runs on a separate machine (headless Mac Mini) and feeds the GCD pipeline autonomously.

### Morning Pipeline

Runs daily at 6:30 AM via LaunchAgent. Scans RSS feeds (via Miniflux) for content signals, scores them against pillars, generates brief stubs for high-signal topics, and logs the run. By the time you sit down, the brief queue is populated and scored.

### Auto-Retro

Runs weekly. Scans the sprint for pieces that reached `published` or `measured` status, pulls engagement metrics, analyzes performance patterns, and writes a structured retrospective. Detects unmatched posts (metrics without content files), looks up post text in LinkedIn data exports, and creates stub files for tracking.

### Voice Drift Analysis

Runs weekly. Compares `.draft.md` files (the AI's original output) against their published siblings (the human-edited version) to detect systematic voice drift. Builds a living `voice-drift.md` document with patterns like "AI over-explains," "human cuts preamble," etc. Also runs an anti-pattern pass on rejected drafts to extract NEVER rules.

### Weekly Report

Runs after auto-retro. Generates a structured weekly report with pipeline throughput, engagement trends, pillar coverage analysis, and velocity metrics. Feeds into the next sprint planning cycle.

### LinkedIn Export Watcher

Runs on the local machine. Watches `~/Downloads/` for LinkedIn data exports, extracts to the vault, and triggers the retro + report chain on the remote machine. Bridges the gap between LinkedIn's manual export process and the automated analytics pipeline.

### Metrics Integration

Engagement metrics flow into frontmatter via two paths:
- **Manual entry** during `/gcd:retro` — the human enters impressions, reactions, comments, shares
- **Auto-fill** via LinkedIn data exports and Tampermonkey userscript — matches published posts to content files by URL and pre-populates metrics

## Getting Started

**Prerequisites:**

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI installed and configured
- An Obsidian vault (or any markdown-based content store)
- Signal briefs in the vault (manually via `/seed-idea` or automated via RSS)

**Install skills:**

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
4. Add signal briefs to your vault's inbox
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

## How It Works

GCD uses YAML frontmatter as the single source of truth for content state. Each piece moves through a defined lifecycle:

```
stub → draft → reviewed → approved → published → measured
                   ↑          |
                   └──────────┘  (revise loop)

              draft/reviewed → rejected  (terminal, preserved for learning)
```

### Sprint Planning

The `gcd-sprint-planner` agent scores signal briefs using a composite formula: keyword match (50%) + pillar fit with underrepresentation boost (30%) + route fit (20%). It loads the most recent performance summary to apply boosts to historically high-performing route+pillar combinations. A 4-week rolling window detects pillar drift — if you haven't posted about a topic in two weeks, the planner surfaces it without hard-blocking.

### Route-Dispatched Drafting

`/gcd:produce` routes each brief to the right agent workflow:
- **LinkedIn post** — direct to `gcd-producer` with voice guide
- **Substack essay** — research phase via `gcd-researcher`, then draft via `gcd-producer`
- **Twitter/X thread** — threaded format with character-aware splitting
- **Newsletter** — section assembly from approved pieces

### Two-Gate Quality

The system separates concerns across two review gates:

**Gate 1 (Agent):** The `gcd-reviewer` catches what machines catch well — style consistency, structural issues, hook quality grading (A/B/C/D), SEO criteria, suggested title variants. Returns pass, revise, or escalate.

**Gate 2 (Human):** `/gcd:approve` catches what humans catch well — tone, judgment, relevance, "does this actually sound like me?" Neither gate alone is enough. Both together cover the full surface.

### Performance Feedback Loop

`/gcd:retro` closes the sprint with pipeline metrics and engagement analysis. The `gcd-metrics-analyst` agent identifies high and low performers by route and pillar. This data feeds back into the sprint planner — next week's scoring applies a +0.1 boost to route+pillar combinations that historically outperform, and a -0.05 penalty to underperformers.

### Voice Learning

Every AI draft is preserved as a `.draft.md` sibling file. When the human edits and publishes the main file, the voice drift analysis compares the pair to detect systematic patterns. Over time, this builds a living document of voice rules that agents read before drafting — a feedback loop between human editing instinct and AI output.

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

## Architecture

```
                    ┌──────────────────┐
                    │  Morning Pipeline │ ← RSS feeds (Miniflux)
                    │  (daily, 6:30 AM)│
                    └────────┬─────────┘
                             │ briefs
                             ▼
┌──────────┐    ┌──────────────────────┐    ┌──────────────────┐
│ /seed    │───▶│     Brief Queue      │◀───│ Content Signals  │
│  -idea   │    │  (scored, filtered)  │    │ (n8n + RSS)      │
└──────────┘    └────────┬─────────────┘    └──────────────────┘
                         │
                         ▼
              ┌─────────────────────┐
              │  /gcd:plan-sprint   │ ← gcd-sprint-planner agent
              │  (interactive)      │    (composite scoring, drift)
              └────────┬────────────┘
                       │ assigns briefs to pillar slots
                       ▼
              ┌─────────────────────┐
              │  /gcd:produce       │ ← gcd-producer + gcd-researcher
              │  (route-dispatched) │    (voice guide, research)
              └────────┬────────────┘
                       │ .draft.md preserved
                       ▼
              ┌─────────────────────┐
              │  /gcd:review        │ ← gcd-reviewer agent
              │  Gate 1 (agent)     │    (voice, structure, SEO)
              └────────┬────────────┘
                       │ pass / revise / escalate
                       ▼
              ┌─────────────────────┐
              │  /gcd:approve       │
              │  Gate 2 (human)     │
              └────────┬────────────┘
                       │
                       ▼
              ┌─────────────────────┐    ┌──────────────────────┐
              │  Published          │───▶│  /gcd:retro          │
              │  (manual post)      │    │  (metrics, analysis) │
              └─────────────────────┘    └────────┬─────────────┘
                                                  │
                       ┌──────────────────────────┘
                       ▼
              ┌─────────────────────┐    ┌──────────────────────┐
              │  Performance Data   │───▶│  Voice Drift         │
              │  (feeds next sprint)│    │  Analysis (weekly)   │
              └─────────────────────┘    └──────────────────────┘
```

## Integrations

| Integration | Role |
|-------------|------|
| **Miniflux** (self-hosted RSS) | Daily content signal scanning — RSS feeds are categorized and scanned for topic convergence, volume spikes, and engagement signals |
| **n8n** (workflow automation) | Orchestrates the morning pipeline — triggers RSS scans, runs signal detection, generates brief stubs |
| **Obsidian** (markdown vault) | Content store — all files live in the vault with YAML frontmatter as the state layer |
| **LinkedIn Data Exports** | Engagement metrics source — `Shares.csv` provides post text for matching, metrics for analysis |
| **Tampermonkey** | Browser userscript for auto-capturing LinkedIn engagement metrics from the UI |
| **LaunchAgent** (macOS) | Schedules the morning pipeline, auto-retro, voice drift analysis, and weekly reports |

## Version History

| Version | Date | What shipped |
|---------|------|-------------|
| **v1.0** | 2026-02-22 | Foundation through retrospectives — state spec, sprint planning, route-dispatched drafting, two-gate quality, retros (Phases 1-6) |
| **v1.1** | 2026-02-23 | Twitter/X thread route, signal scoring display, engagement metrics in retro, strategy drift + velocity tracking, performance feedback loop (Phases 7-11) |
| **v1.2** | In progress | LinkedIn metrics auto-fill via data exports + Tampermonkey, reject skill with anti-pattern learning |

## Contributing

Issues and PRs welcome. If you're adapting GCD for a different content workflow, I'd genuinely like to hear about it.

## License

[MIT](LICENSE)

<div align="center">

---

**Built by [Rebecca Rae Barton](https://github.com/thatrebeccarae)**

Give your content the same rigor your code gets.

</div>
