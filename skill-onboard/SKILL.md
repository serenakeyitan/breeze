---
name: breeze-onboard
description: |
  Set up breeze (GitHub PR auto review) on this machine. Asks only what
  is still unanswered, then writes an explicit owner/repo allowlist and
  can start the daemon. Tray is optional and off by default.
  Use when: "onboard breeze", "set up breeze", "install breeze",
  "/breeze-onboard", "breeze setup", first-time breeze install.
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
---

# breeze-onboard

Ask the user. Do not run a linear wizard. Probe first. Chat answers count
for every decision (repos, tray, start), not only tray.

Never write `repos: all`. Never start without `owner/repo`. Never install
tray unless they opt in.

## 1. Probe

```bash
LINK=""
[ -L "$HOME/.claude/skills/breeze-onboard" ] && LINK="$HOME/.claude/skills/breeze-onboard"
[ -z "$LINK" ] && [ -L "$HOME/.agents/skills/breeze-onboard" ] && LINK="$HOME/.agents/skills/breeze-onboard"
REPO=""
if [ -n "$LINK" ]; then
  TARGET="$(readlink "$LINK")"
  REPO="$(cd "$(dirname "$TARGET")" && pwd)"
fi
[ -z "$REPO" ] && [ -x "$HOME/breeze/bin/breeze-onboard-probe" ] && REPO="$HOME/breeze"
[ -z "$REPO" ] && [ -x "$(pwd)/bin/breeze-onboard-probe" ] && REPO="$(pwd)"
PROBE="$REPO/bin/breeze-onboard-probe"
if [ -z "$REPO" ] || [ ! -f "$PROBE" ]; then
  echo "PROBE_MISSING"
else
  chmod +x "$PROBE" "$REPO/bin/breeze-onboard-apply" 2>/dev/null || true
  bash "$PROBE"
fi
```

If `PROBE_MISSING`: tell them exactly this and stop (no other questions):

`git clone https://github.com/serenakeyitan/breeze.git ~/breeze && cd ~/breeze && ./setup`

Then: run `/breeze-onboard` again.

If `gh_ok` is false: tell them `gh auth login`, then re-run `/breeze-onboard`.
Write nothing. Start nothing.

## 2. Decide without extra asks

A decision is **closed** if this chat already answered it, or probe already
has a valid value.

### Repos (required)

Closed if `config_repos` is a non-empty explicit list **and** `config_is_all`
is false **and** they did not ask to change it.

Still open (must ask or take from chat): empty list, or `config_is_all`.
Do not offer “keep all”. Reject `all`, `*`, globs; re-ask that one
question. “Add X” while a list exists means **union** with current
`config_repos`, not replace.

If they already named valid `owner/repo` in chat, do not open the picker.

### Tray (optional)

Default: skip. Never `--tray` unless they explicitly want it.

Do **not** offer tray when:
- not Darwin
- they said no / skip / don’t want tray
- this is a returning run (`config_exists` and allowlist already valid)
- they only asked to write config / not start

On Darwin + first run + they said nothing about tray: you may offer
**once**, recommended **Skip tray**.

### Runtime (optional)

Closed if `runtime_saved` is `grok`, `codex`, or `claude` **and** they
did not ask to change it.

Still open on first run, or if they said “use grok / claude / codex”.
Chat answers count. Valid values only: `grok`, `codex`, `claude`.

To switch later without touching repos: run
`breeze-runner runtime grok` (or `/breeze-runtime`). Do **not** call
apply just to change runtime.

On first run with no mention: you may ask **once**. Recommend whichever
of grok/codex/claude is actually on PATH.

### Start

Closed if they already said start or don’t start.

If the allowlist **changed** and `runner_running` is true: do **not** ask.
Restart (`--start`) so the live process matches the new list.

If `runner_running` is false and they said “set up breeze” / onboard with
no “don’t start”: treat start as yes (say so in the report).

If there is no runner binary and `cargo_ok` is false: do not ask start.
Write config, tell them they need Rust, how to start later.

If `runner_running` is true and the list is unchanged: do not ask, do not
restart, do not call apply unless they asked to change something.

Do not ask poll interval (10 minutes).

## 3. Apply (only if something must change)

```bash
APPLY="$REPO/bin/breeze-onboard-apply"
# example after chat “只要 tornado-doc/tdoc，不要 tray，启动”
bash "$APPLY" --allow-repo tornado-doc/tdoc --runtime grok --start
```

Pass `--runtime grok|codex|claude` when that decision is new or changed.
Pass `--tray` / `--open-tray` only on explicit opt-in. Pass `--start` to
start or restart. If they only want to switch runtime and the allowlist
is already valid: skip apply, run `"$REPO/breeze-runner/target/release/breeze-runner" runtime <name>`.
If nothing changed and daemon is already correct: skip apply, just report.

Symlink skills if missing:

```bash
mkdir -p "$HOME/.claude/skills"
ln -sfn "$REPO/skill" "$HOME/.claude/skills/breeze"
ln -sfn "$REPO/skill-watch" "$HOME/.claude/skills/breeze-watch"
ln -sfn "$REPO/skill-upgrade" "$HOME/.claude/skills/breeze-upgrade"
ln -sfn "$REPO/skill-onboard" "$HOME/.claude/skills/breeze-onboard"
ln -sfn "$REPO/skill-runtime" "$HOME/.claude/skills/breeze-runtime"
```

## 4. Report

Re-run probe. Tell them:

- GitHub login breeze will post as
- allowlist
- review runtime (`agent:` from `breeze-runner status`, or `breeze-runner runtime`)
- daemon running or not (from `breeze-runner status` `allowed repos`, not
  only the yaml)
- tray only if Darwin: installed, skipped, or failed (failure is not fatal)
- if daemon is down: `breeze-runner start --allow-repo <the list>`

Remind once: PRs are reviewed only on `review_requested` to this account
(CODEOWNERS or a manual review request).
