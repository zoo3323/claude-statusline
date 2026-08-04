# claude-statusline

**English** · [한국어](README.ko.md)

A one-line status line for the Claude Code CLI: Claude and Codex usage, the
context window, Codex run state, and the task in progress.

![statusline preview](assets/statusline.svg)

## Features

- codex / claude usage gauges (5-hour window left + weekly usage + time to reset)
- Usage that keeps moving while you are idle — polled in the background, not only after you prompt
- Codex run state (idle / working, plus how many calls are in flight)
- Context gauge
- Task in progress
- `/refresh` or `cu-refresh` to refresh usage on the spot

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/zoo3323/claude-statusline/main/install-claude-statusline.sh | bash
```

If `jq` is missing it is fetched into `~/.local/bin`, no admin rights required.
Restart Claude Code and the status line appears.

## Reading a usage gauge

| part | meaning |
| --- | --- |
| bar length | share of the 5-hour window still left (drains from 100%) |
| block height `▁▂▃▄▅▆▇█` | weekly quota still left — the bar flattens as the week is spent |
| colour | theme colour normally, yellow under 30% left, red under 10% |
| `↻1h23m` | time until the 5-hour window resets (`↻6d3h` for a weekly-only window) |

## Where the numbers come from

Claude Code hands the status line a `rate_limits` block, but only refills it after
an API response. On its own that means an idle session keeps painting the numbers
it last saw, and once a window resets it keeps painting them for hours. So the
status line reads three sources and draws the freshest of them:

1. the payload Claude Code just handed it,
2. the last payload any session received (`~/.claude/codex-status/claude-last-input.json`),
3. a background poll of your account usage, at most once every 5 minutes.

Usage only climbs until a window resets, which is what makes "freshest" decidable:
a later `resets_at` means a newer window, and inside one window the larger number
is the more recent reading. A window whose reset time has already passed is drawn
as empty rather than as the numbers from the window before it.

The poll reuses the OAuth token Claude Code already stores on this machine
(`~/.claude/.credentials.json`, falling back to the macOS Keychain) and calls
`api.anthropic.com/api/oauth/usage`. Codex usage works the same way against
`chatgpt.com/backend-api/wham/usage`, using `~/.codex/auth.json`. Both are
account-info requests, not model requests: they consume no usage, and nothing is
sent anywhere else. Neither endpoint is a documented API, so if either changes or
answers with an error, the cache is left untouched and the gauge falls back to
what Claude Code reports.

## Usage

- Refresh now: `cu-refresh` in a terminal, `/refresh` inside Claude Code
- The Codex parts only appear when Codex MCP is wired into Claude Code

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/zoo3323/claude-statusline/main/uninstall-claude-statusline.sh | bash
```

Reverts exactly what the installer touched — the status line scripts, the
`statusLine` and Codex hook entries in `settings.json`, and the `cu-refresh`
alias. Everything else is left alone.

## What it installs

| path | what it is |
| --- | --- |
| `~/.claude/scripts/statusline-codex.sh` | the status line itself |
| `~/.claude/scripts/claude-usage-refresh.sh` | polls Claude account usage into a cache |
| `~/.claude/scripts/codex-usage-refresh.sh` | polls Codex account usage into a cache |
| `~/.claude/scripts/usage-refresh.sh` | refreshes both right now (`cu-refresh`, `/refresh`) |
| `~/.claude/scripts/codex-status-set.sh` | hook that counts in-flight Codex calls |
| `~/.claude/skills/refresh/SKILL.md` | the `/refresh` skill |
| `~/.claude/codex-status/` | usage caches and per-session counters |
