# GitHub PR auto review

**breeze** reviews pull requests from **your** GitHub account. A local daemon watches review requests, uses your coding plan, and posts the audit as you. It runs on your machine. The macOS menu bar tray is optional.

```
/breeze: 52 PRs · 3 issues · 1 discussions (+2 new)
```

## Onboard

Two steps. The first only installs tools. The second asks you which repo to review, then starts the daemon.

### 1. Install tools

Prerequisites: [GitHub CLI](https://cli.github.com/) (`gh auth login`, `repo` scope), [jq](https://jqlang.github.io/jq/), [Rust](https://rustup.rs/) (`cargo`, needed to build and start the daemon), and a coding agent that can run skills (Claude Code, Codex, Grok, …).

```bash
git clone https://github.com/serenakeyitan/breeze.git ~/breeze
cd ~/breeze
./setup
```

`./setup` links `/breeze` and `/breeze-onboard`, and builds `breeze-runner` if `cargo` is available. It does **not** start reviewing. It never writes `repos: all`.

### 2. Tell your coding agent `/breeze-onboard`

That skill looks at what is already done and asks only what is still open. You can answer in one sentence:

> just `owner/repo`, no tray, start the daemon

It will:

1. Stop if `gh` is not logged in (`gh auth login`, then run `/breeze-onboard` again).
2. Ask which **`owner/repo`** to review. Explicit list only — never `all`, never `org/*`.
3. Ask which **runtime** reviews PRs: `grok`, `codex`, or `claude`. You can change it later.
4. Start the daemon on that allowlist (unless you say not to). Poll interval is 10 minutes.
5. On macOS, offer the menu bar tray **once**. Default is skip. Say you want the tray if you want it.

When it finishes, breeze posts as whatever `gh` is logged in as. PRs are reviewed only when that account is requested as a reviewer (CODEOWNERS or a manual review request).

### Later

| You want to… | Do this |
|---|---|
| Add another repo | `/breeze-onboard` again and name it. Existing repos stay; the daemon restarts with the union. |
| See status | `/breeze-onboard` again, or `breeze-runner status` |
| Write config only | say the repos and “don’t start” |
| Install the tray later | `/breeze-onboard` and say you want the tray |
| Switch review runtime | `/breeze-runtime grok` (or `codex` / `claude`), or `breeze-runner runtime grok` |

Do not edit `~/.breeze/config.yaml` to `repos: all`. If an old config has `all`, `/breeze-onboard` will ask you to pick explicit repos before anything starts.

## What it does

1. **Reviews PRs** on the repos you allowlisted, as your GitHub user, when you are requested as reviewer
2. **Polls GitHub** for your notifications (PRs, issues, discussions, review requests, mentions)
3. **Shows a summary** in your Claude Code statusline with a terminal bell on new items
4. **Type `/breeze`** to see your inbox grouped by project with clickable GitHub links
5. **Pick a notification** and the agent summarizes the context, suggests an action with a confidence level
6. **Act on it** in natural language ("approve this PR", "mark for human review", "this is handled")

breeze uses **GitHub labels** to track notification status. The source of truth lives on GitHub, not your laptop. This means the state is visible to your team, visible on github.com, and survives if you reinstall.

## Why not a loop, Greptile, or Copilot

The review job is a loop: poll GitHub, see `review_requested`, run an agent, comment as you. A 40-line script can do that once. breeze is that loop plus the shell you need if it is going to stay correct.

| | Your own loop | Greptile / Copilot | breeze |
|---|---|---|---|
| Who comments | You, if you wired `gh` | Their bot (`greptile-apps`, Copilot) | **You** — same account as `gh auth` |
| Whose model / bill | Whatever you hardcoded | Their cloud, their seat | **Your existing token subscription** (Claude, Codex, Grok, …) |
| Review style | Whatever you pasted into the script | Their default + a rules file | **Your coding plan**, in your agent session |
| Where it runs | A terminal you must keep open | Their servers, via a GitHub App or org Copilot seats | Your machine, scoped to `owner/repo` |
| State after restart | Easy to re-review or miss | Their dashboard | GitHub labels (`breeze:wip` / `human` / `done`) |
| When you are needed | Script has no inbox | Their UI / mention the bot | `/breeze`, statusline, optional tray |

**vs a loop.** Same kernel. The loop does not remember work across restarts, does not stop two agents from reviewing the same PR, does not give you a place for the 1% that needs a human, and dies when the session dies. breeze keeps an allowlist (never `repos: all`), claim locks, labels on GitHub, and a daemon you can pause, add a repo to, or ask “what is in the inbox.”

**vs Greptile.** No GitHub App on the org. After a repo moves orgs, Greptile goes silent until someone reinstalls their app. breeze does not care — it is your `gh` login on your laptop. Comments look like a teammate reviewed, not a vendor bot. You already pay for a coding-agent subscription; you do not buy another review product.

**vs GitHub Copilot review.** Copilot needs Copilot seats on the org and posts as Copilot. Zero seats means zero reviews. breeze uses the agent you already run locally. Same as Greptile: the audit is yours, on your token, as your user.

If you only want one repo auto-audited tonight, write a loop. If you want a GitHub presence that stays scoped, restarts cleanly, and spends your own subscription instead of a bot vendor, use breeze.

## Commands

- **`/breeze-onboard`** — set up or change which repos to review; pick a runtime; start the daemon; tray is optional
- **`/breeze-runtime`** — show or switch the review agent (`grok`, `codex`, `claude`)
- **`breeze-runner runtime [grok|codex|claude]`** — same switch from the terminal
- **`/breeze`** — open the inbox dashboard, pick a notification, act on it
- **`/breeze-watch`** — live activity log with clickable GitHub links, in a new terminal window
- **`/breeze-upgrade`** — pull the latest code (no restart needed)
- **`http://127.0.0.1:7878`** — live web dashboard (when the unified daemon is installed)
- **menu bar tray** — optional; Pause/Resume the daemon and open PRs labeled `breeze:human` (`tray-mac/`)

## Usage

In Claude Code, type `/breeze` to open your inbox grouped by project.

```
/breeze inbox — 15 new · 3 wip · 5 human · 50 done

### paperclip (10)
  1. [PR] feat: add OAuth support (review_requested)
     https://github.com/paperclipai/paperclip/pull/305
  2. [Issue] bug: broken login on mobile (mention)
     https://github.com/paperclipai/paperclip/issues/3700

### paperclip-tree (3)
  1. [PR] sync: add MCP server (author)
     https://github.com/serenakeyitan/paperclip-tree/pull/266
```

Pick a number. The agent loads the full context (PR diff, comment thread, issue body), summarizes it, and suggests an action. Tell it what to do in plain English.

## Notification Status

breeze tracks status using **GitHub labels** on the PR/issue/discussion:

| Label | Status | Meaning | Shows in statusline? |
|-------|--------|---------|---------------------|
| *(none)* | **new** | Needs action, no one's on it | Yes |
| `breeze:wip` | **wip** | Agent or human is actively working | No |
| `breeze:human` | **human** | Escalated to human judgment | No |
| `breeze:done` | **done** | Handled, no more action needed | No |

Additionally, PRs that are **merged** or **closed** on GitHub are treated as `done` automatically (no label needed).

The statusline only counts **new** notifications. The number is stable across terminals because state lives on GitHub — same labels, same count, every machine.

### Status commands

- `"resolve #3"` or `"mark #3 done"` — applies `breeze:done` label
- `"I'll handle this"` or `"escalate to human"` — applies `breeze:human` label
- `"working on it"` — applies `breeze:wip` label (agent lock)
- `"show wip"` or `"show done"` — filter by status

### Agent claim locks

When an agent starts working on a notification, it claims it with an atomic filesystem lock at `~/.breeze/claims/<id>/`. Other agents see the claim and skip it. Claims auto-expire after 5 minutes if the agent crashes.

## Config

Edit `~/.breeze/config.yaml`:

```yaml
repos:
  - owner/repo             # explicit only — never `all`
poll_interval: 600         # 10 minutes
footer: true               # append "This comment is from breeze" + repo link
```

Prefer `/breeze-onboard` over hand-editing this file. The daemon also needs `--allow-repo owner/repo` when it starts; onboard writes both.

## How it works

```
GitHub API  →  Poller (launchd)  →  ~/.breeze/inbox.json  →  Statusline
     ↑                                     ↓
     │                              /breeze skill (dashboard + actions)
     │                                     ↓
     │                          claims/<id>/ (agent locks)
     │                                     ↓
     └──────────  gh label   ←──── apply breeze:{wip,human,done}
```

State lives on GitHub via labels. The local inbox.json is just a cache of what GitHub sent us plus the current label-derived status.

## Vision

GitHub goes agent-first.

Your agent talks to their agent. They handle the PRs, the comments, the issues, the discussions. They negotiate reviews, close dupes, push stuff through CI, ping you when it matters.

Agents handle 99%. Humans see 1%.

That 1% is the part that needs you — real decisions, real judgment. Everything else was never your job, you just got stuck doing it.

breeze is how we get there. See [DESIGN.md](DESIGN.md) for the architecture. See [tray-mac/README.md](tray-mac/README.md) for the menu bar app.

## License

MIT
