# Content Pipeline — Daily Feed Intelligence + Morning Production

End-to-end autonomous content pipeline: RSS signal detection → sprint planning → draft production → editorial review → Slack notification.

- **n8n Workflow ID:** `GpI5N6fVzQuVw3W2`
- **Morning Pipeline:** `~/morning-pipeline.sh` (LaunchAgent: `com.gcd.morning-pipeline`)
- **Runs on:** your macOS host
- **Schedule:** DFI at 6:00 AM ET daily, Morning Pipeline at 6:30 AM ET daily

## Architecture

```
6:00 AM  DFI workflow (n8n, Docker)
         ├─ RSS fetch (Miniflux, last 25h)
         ├─ Parallel: Digest + Signal Detection + Article Scout
         ├─ Gemini scoring (strategy fit, angles, hooks)
         ├─ Flag ExecPR signals → execpr-flags/YYYY-MM-DD.json
         ├─ Generate brief stubs → briefs/YYYY-MM-DD-slug.md
         ├─ Auto-assign sprint (pillar mapping, scheduling, conflict detection)
         └─ Slack notification to #content-pipeline

6:30 AM  morning-pipeline.sh (host cron, outside Docker)
         ├─ Auto-sprint-plan: if no sprint-assigned stubs, assign top 3 by impact score
         ├─ Find sprint-assigned stubs scheduled within next 10 days
         ├─ For each: claude --print → produce draft
         ├─ For each: claude --print → editorial review
         ├─ If revise: loop produce→review (max 3 attempts)
         ├─ Process ExecPR flags → campaign-tracker
         └─ Slack notification: "N drafts ready for review"

~8-9 AM  Human review
         ├─ /gcd:approve [piece-id] for each draft
         └─ Review ExecPR opportunities
```

## Usage

```bash
# Export live workflow from n8n (run on your host, or set up SSH tunnel first)
./export.sh

# Deploy repo version to n8n
./deploy.sh

# Run morning pipeline manually
ssh user@your-server 'export PATH="~/.local/bin:~/.nvm/versions/node/v22.22.0/bin:$PATH" && bash ~/morning-pipeline.sh'
```

## Signal Detection

Topics are extracted as 2-grams and 3-grams from article titles, then filtered:

- **Pillar gate:** Must match at least 1 content pillar (Building with AI, E-Commerce Strategy, Career & Leadership, Pillar Four)
- **Generic bigram blocklist:** Common phrases ("open source", "best practices", etc.) are excluded to prevent false convergence
- **Convergence tiers:** Tier 1 (High): 3+ categories or 5+ mentions. Tier 2 (Medium): 2+ categories with shared pillar context, or 3+ feeds. Tier 3 (Low): pillar-matched topic with 2+ mentions from any source mix.
- **Volume spikes:** Count > 2x baseline average (7-day rolling)

### Urgency Tiers

| Tier | Criteria | Action |
|------|----------|--------|
| Routine | impact < 30 | Normal sprint assignment (2-day buffer) |
| High-signal | impact 30-40 AND fit >= 8 | Slack alert, no auto-displacement |
| Breaking | impact > 40 OR sources >= 6 | Slack alert with displacement candidates |

Breaking/high-signal alerts flag opportunities but never auto-bump scheduled content. Human decides.

## Sprint Assignment

- **Pillars:** Mon=Building with AI, Tue=E-Commerce Strategy, Wed=Career & Leadership, Thu=Essays
- **Piece ID format:** `WNN-DD` (ISO week + day index)
- **Scheduling:** Finds next occurrence of pillar's day, minimum 2-day buffer from today
- **Conflict detection:** Checks existing briefs for duplicate sprint+piece_id

## Morning Pipeline Details

- **Auto-sprint-planning:** If no sprint-assigned stubs exist, auto-assigns the top 3 unassigned briefs (by `impact_score`) to the current week. Uses the brief's `linkedin_slot` to pick scheduled day, with fallback spacing.
- **Brief selection:** All `*.md` briefs with `status: stub` + `sprint:` assigned + `scheduled:` within next 10 days
- **Draft production:** `claude --print` with brief content + voice guide embedded in prompt (--print has no file tool access)
- **Editorial review:** `claude --print` with DECISION:pass/revise protocol
- **Revision loop:** If revise, applies editor's inline `<!-- REVIEW: -->` comments and re-submits (max 3 attempts)
- **Output paths:** LinkedIn → `standalone/linkedin/`, Essay → `articles/drafts/slug/`, Twitter → `standalone/twitter/`
- **Logs:** `01-Inbox/pipeline-runs/YYYY-MM-DD-morning.log`
- **Auth:** `claude setup-token` on your host (file-based, uses Claude Max subscription — not API key)

## ExecPR Signals

DFI flags career/leadership signals as ExecPR opportunities:
- Saved to `01-Inbox/content-signals/execpr-flags/YYYY-MM-DD.json`
- Morning pipeline appends to `03-Areas/executive-pr/campaign-tracker.md`

## Notifications

All notifications go to Slack **#content-pipeline** (`SLACK_CONTENT_CHANNEL_ID`):
- DFI run → digest summary + sprint assignments + ExecPR flag count
- Morning pipeline → drafts produced with review decisions + Obsidian deep links
- Miniflux failure → error details

## Files

| File | Location | Purpose |
|------|----------|---------|
| `workflow.json` | This repo | DFI n8n workflow definition |
| `morning-pipeline.sh` | This repo + `~/morning-pipeline.sh` on your host | Host-level production script |
| `deploy.sh` | This repo | Deploys workflow.json to n8n API |
| `export.sh` | This repo | Exports live workflow from n8n |
| LaunchAgent | `~/Library/LaunchAgents/com.gcd.morning-pipeline.plist` | Triggers morning-pipeline.sh daily |

## Related

- Workflow docs: `~/your-vault/...
- Pillars config: `~/your-vault/...
- Voice guide: `~/your-vault/...
- Claude skill: `/write-from-signal` reads generated briefs and routes through agent chains
