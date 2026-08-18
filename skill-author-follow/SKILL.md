---
name: breeze-author-follow
description: |
  Show or switch which allowlisted repos also get reviews on PRs
  this GitHub account opened. Optional; off by default.
  Use when: "follow my own PRs", "author-follow", "也跟我自己开的 PR",
  "/breeze-author-follow", "stop reviewing my PRs", "author follow off".
allowed-tools:
  - Bash
  - Read
---

# breeze-author-follow

Optional switch. Same picker as the repo allowlist, but it only reviews
PRs **you** opened. GitHub will not `review_requested` the author.

Valid values: `off` / `none`, or explicit `owner/repo` values that are
already on the breeze allowlist. Never `all`. Chat answers count. Do
not ask poll interval, tray, or runtime.

## 1. Find the binary

```bash
LINK=""
[ -L "$HOME/.claude/skills/breeze-author-follow" ] && LINK="$HOME/.claude/skills/breeze-author-follow"
[ -z "$LINK" ] && [ -L "$HOME/.claude/skills/breeze-onboard" ] && LINK="$HOME/.claude/skills/breeze-onboard"
REPO=""
if [ -n "$LINK" ]; then
  TARGET="$(readlink "$LINK")"
  REPO="$(cd "$(dirname "$TARGET")" && pwd)"
fi
[ -z "$REPO" ] && [ -x "$HOME/breeze/breeze-runner/target/release/breeze-runner" ] && REPO="$HOME/breeze"
RUNNER="$REPO/breeze-runner/target/release/breeze-runner"
```

If the binary is missing: tell them to `cd ~/breeze && ./setup`, then stop.

## 2. Decide

Show current:

```bash
"$RUNNER" author-follow
"$RUNNER" status
```

If this chat already said `off` / `none` / “不要跟我自己的 PR”, target is
off. If they named valid allowlisted `owner/repo` values, that list is
the target. “Add X” unions with the current live list.

Otherwise ask **once**. Options: **Off** (default), each current
allowlisted repo, Other (must already be on the allowlist).

If they name a repo that is not allowlisted: tell them to add it with
`/breeze-onboard` first. Do not start unscoped.

## 3. Apply

```bash
"$RUNNER" author-follow off
"$RUNNER" author-follow serenakeyitan/tokentorrent
"$RUNNER" author-follow tornado-doc/tdoc,serenakeyitan/tokentorrent
```

This keeps the allowlist, poll, HTTP port, and runtime. It restarts the
daemon if it is running.

## 4. Report

Re-run `"$RUNNER" author-follow` and `"$RUNNER" status`. Tell them
author-follow is off or which repos it covers.
