---
name: breeze-runtime
description: |
  Show or switch the breeze review runtime (grok, codex, or claude).
  Use when: "switch breeze runtime", "use grok", "use claude", "use
  codex", "/breeze-runtime", "change breeze agent", "breeze runtime".
allowed-tools:
  - Bash
  - Read
---

# breeze-runtime

Switch which local coding agent reviews PRs. Valid values: `grok`,
`codex`, `claude`. Chat answers count. Do not ask poll interval or repos.

## 1. Find the binary

```bash
LINK=""
[ -L "$HOME/.claude/skills/breeze-runtime" ] && LINK="$HOME/.claude/skills/breeze-runtime"
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

If this chat already named `grok`, `codex`, or `claude`, that is the
target. Synonyms: “xai” / “grok.com” → grok; “gpt” / “openai” → codex;
“anthropic” / “sonnet” / “opus” → claude.

Otherwise show current and ask once:

```bash
"$RUNNER" runtime
```

Do not offer a runtime whose binary is missing unless they insist.

## 3. Apply

```bash
"$RUNNER" runtime grok
```

This writes `~/.breeze/runtime` and restarts the daemon with the same
allowlist, 10-minute poll, and HTTP port.

## 4. Report

Re-run `"$RUNNER" runtime` and `"$RUNNER" status`. Tell them the live
agent and that the next review uses it.
