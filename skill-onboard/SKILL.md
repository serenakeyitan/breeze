---
name: breeze-onboard
description: |
  Set up breeze (GitHub PR auto review) on this machine. Asks only the
  questions that are still unanswered, then writes config, starts the
  daemon, and optionally installs the macOS tray.
  Use when: "onboard breeze", "set up breeze", "install breeze",
  "/breeze-onboard", "breeze setup", first-time breeze install.
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
---

# breeze-onboard

Drive breeze setup by asking the user. Do **not** run a linear wizard
script that asks every question. Probe first, skip what is already
decided, and let the user change their mind in chat.

Never write `repos: all`. Never start the daemon without an explicit
`owner/repo` allowlist.

## 1. Probe

Find the repo (this skill lives at `<repo>/skill-onboard`):

```bash
SKILL_FILE=""
[ -f "$HOME/.claude/skills/breeze-onboard/SKILL.md" ] && SKILL_FILE="$HOME/.claude/skills/breeze-onboard/SKILL.md"
[ -z "$SKILL_FILE" ] && [ -f "$HOME/.agents/skills/breeze-onboard/SKILL.md" ] && SKILL_FILE="$HOME/.agents/skills/breeze-onboard/SKILL.md"
REPO=""
if [ -n "$SKILL_FILE" ]; then
  REPO="$(cd "$(dirname "$(readlink "$SKILL_FILE" 2>/dev/null || echo "$SKILL_FILE")")/.." && pwd)"
fi
[ -z "$REPO" ] && [ -d "$HOME/breeze/bin" ] && REPO="$HOME/breeze"
PROBE="$REPO/bin/breeze-onboard-probe"
if [ ! -x "$PROBE" ]; then
  echo "PROBE_MISSING"
else
  bash "$PROBE"
fi
```

If `PROBE_MISSING`: tell them to `git clone https://github.com/serenakeyitan/breeze.git` and stop.

Parse the JSON. If `gh_ok` is false: tell them to run `gh auth login` and stop.

If they already stated repos / tray / start in this chat, treat that as
the answer. Do not re-ask.

## 2. Ask only what is still open

Use `AskUserQuestion` when it exists. If it does not, ask in prose and wait.
One question at a time. After each answer, continue.

### Repos (required)

Ask if `config_repos` is empty **or** `config_is_all` is true **or** they
said they want to change the list.

- Build options from `recent_repos` (split on commas), plus any current
  `config_repos` that are not `all`.
- Recommend repos they actually use (if `tornado-doc/tdoc` is in the list,
  put it first).
- Allow multiple. Always keep an "Other" / type `owner/repo` path.
- Reject `all`, `*`, and anything that is not `owner/repo`. Re-ask.

If a valid allowlist already exists and they did not ask to change it,
keep it and say so.

### Tray (macOS only)

Ask only if `os` is `Darwin`. Skip on Linux.

- If `swift_ok` is false: say tray needs Swift CLT, skip, do not fail setup.
- If `tray_installed` is true: default to leave it; only ask if they want
  it opened.
- Otherwise: install + open, or skip.

### Start daemon

Ask only if `runner_running` is false, or the repo list just changed.

- Yes: start with the allowlist.
- No: write config only.

If `cargo_ok` is false and they want start: tell them they need Rust to
build `breeze-runner`, do not pretend the shell poller is scoped.

Do **not** ask poll interval. It is 10 minutes.

## 3. Apply

```bash
APPLY="$REPO/bin/breeze-onboard-apply"
FLAGS=(--allow-repo "owner/repo,owner/repo2")
# add --tray --open-tray --start from answers
bash "$APPLY" "${FLAGS[@]}"
```

Also symlink skills if `~/.claude/skills/breeze-onboard` is missing:

```bash
mkdir -p "$HOME/.claude/skills"
ln -sfn "$REPO/skill" "$HOME/.claude/skills/breeze"
ln -sfn "$REPO/skill-watch" "$HOME/.claude/skills/breeze-watch"
ln -sfn "$REPO/skill-upgrade" "$HOME/.claude/skills/breeze-upgrade"
ln -sfn "$REPO/skill-onboard" "$HOME/.claude/skills/breeze-onboard"
```

## 4. Report

Re-run the probe. Tell them, in this order:

- GitHub login breeze will post as
- allowlist
- daemon running or not
- tray installed / opened or skipped
- dashboard URL if the daemon is up (`breeze-runner status` / probe)

Remind once: a PR is reviewed only when GitHub sends you
`review_requested` (CODEOWNERS or a manual review request).
