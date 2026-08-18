# breeze onboard — user journeys

Source of truth for the flow: `skill-onboard/SKILL.md`, `bin/breeze-onboard-probe`,
`bin/breeze-onboard-apply`, `setup`.

Hard rules: never `repos: all`; never start without `owner/repo`; tray optional
and off by default; author-follow optional and off by default (same picker
as repos); poll is 10 minutes and is not asked.

Simplest UX: fewest questions, no dead ends, chat answers count, skip what
is already decided.

## Journeys

### J1 — Chat already decided
User: first clone, `gh` ok, cargo ok, macOS. Says “只要 tornado-doc/tdoc，不要 tray，启动 daemon”.
Expected questions: **0**.
Apply: `--allow-repo tornado-doc/tdoc --no-author-follow --start` (no `--tray`).
Or omit author-follow flags if they never mentioned it (apply keeps off).

### J2 — First-time, says nothing extra
User: first clone, `gh` ok, cargo ok, Swift ok, macOS. Only “set up breeze”.
Expected: ask repos (from recent list + Other). Offer tray once, **recommend Skip**. Ask start if daemon is down.
Not expected: poll interval, Linux-only stuff, fail if they skip tray.

### J3 — `gh` not logged in
User: runs onboard, probe `gh_ok=false`.
Expected: stop and tell them `gh auth login`. No config write, no start, no tray.

### J4 — Returning, good config, daemon already running
User: `config_repos=tornado-doc/tdoc`, not all, `runner_running=true`.
Expected: keep allowlist, do not re-ask repos or start. Do not install tray.
Report current state.

### J5 — Returning, dangerous `repos: all`
User: old config has `all`.
Expected: must ask for explicit `owner/repo`. Refuse to start until they pick. Never keep `all`.

### J6 — No Rust
User: `cargo_ok=false`, wants start.
Expected: write config if they gave repos. Do not start a fake unscoped poller. Tell them they need cargo to build `breeze-runner`.

### J7 — Linux
User: `os!=Darwin`.
Expected: never mention installing tray as a required step. Repos + start only.

### J8 — Explicitly wants tray
User: macOS, Swift ok, “装 tray 并打开”.
Expected: `--tray --open-tray` after repos. Still succeed if tray build fails? Skill currently can still succeed onboard without tray if install fails — apply prints SKIP/installs. Prefer: try install, report failure, daemon still starts.

### J9 — Bad repo then recover
User: types `all` or `acme/*`, then `tornado-doc/tdoc`.
Expected: reject, re-ask, then apply the good value.

### J10 — Change allowlist while daemon is running
User: had `tornado-doc/tdoc` running, now adds another repo.
Expected: ask/confirm new list, restart daemon with the new `--allow-repo`.

### J11 — Repo not cloned / probe missing
User: no breeze checkout.
Expected: tell them to clone `https://github.com/serenakeyitan/breeze.git`. Stop.

### J12 — Config only, do not start
User: gives repos, says don’t start now.
Expected: write config, no `start`, no tray. Report how to start later.

### J13 — First-time, no mention of own PRs
User: first clone, picks allowlist, says nothing about author-follow.
Expected: author-follow stays **off**. Do not pass `--author-follow-repo`.
May ask once with **Off** recommended.

### J14 — Wants own PRs on one allowlisted repo
User: allowlist is `tornado-doc/tdoc,serenakeyitan/tokentorrent`. Says
“tokentorrent 也跟我自己开的 PR”.
Expected: `--author-follow-repo serenakeyitan/tokentorrent`. Do not turn
it on for tdoc.

### J15 — Returning, author-follow already set
User: live author-follow is `serenakeyitan/tokentorrent`, they did not
ask to change it.
Expected: do not re-ask. Do not turn it off.

### J16 — Turn author-follow off
User: “不要再跟我自己的 PR”.
Expected: `--no-author-follow` or `breeze-runner author-follow off`.
Restart if the daemon is running. Allowlist unchanged.

## Rubric (each journey)

Score 1–5 each:

- **Questions:** only necessary asks (5 = none extra)
- **Defaults:** skip/optional things stay off unless opted in
- **Recovery:** bad input is re-asked, not a crash
- **Safety:** cannot start unscoped / `all`
- **Time-to-useful:** path to “reviewing my repo as me”

A journey fails UX if it asks more than the Expected questions, installs tray without opt-in, or writes `all`.

## Agent eval (2026-08-14)

12 isolated agents walked the skill. Mechanics (`test-journeys.sh`): pass.

| ID | Verdict | Extra asks / hole |
|----|---------|-------------------|
| J1 chat decided | pass | Skill text could still fire repo picker if agent is sloppy |
| J2 first-time quiet | pass | 3 asks; start should default yes on “set up breeze” |
| J3 no gh | pass | 0 asks, no write |
| J4 returning running | **fail** | Might still offer tray once |
| J5 repos all | pass | Must replace all; do not keep it |
| J6 no cargo | pass | Do not ask start if no binary |
| J7 Linux | pass | Do not ask tray |
| J8 wants tray | **fail** | Tray build fail aborted apply before `--start` |
| J9 bad then recover | pass | Apply rejects; skill re-asks |
| J10 add repo | **fail** | Extra start ask; “add” must union |
| J11 no clone | **fail** | Clone URL had no `~/breeze && ./setup` |
| J12 config only | pass | Report must say how to start later |

Fixes landed after eval: chat closes all asks; no tray offer on returning/config-only; apply starts daemon before tray and does not fail onboard if tray install fails; open-tray does not imply login autostart; J11 clone line includes setup; add-repo is union + restart without re-asking start.
