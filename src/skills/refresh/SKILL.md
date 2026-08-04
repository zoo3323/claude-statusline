---
name: refresh
description: Refresh the Codex and Claude usage gauges right now and report the numbers. Use when the user asks for "/refresh", "refresh usage", or "show me my usage now".
---

# refresh

Both usage gauges refresh in the background at most once every 5 minutes, so the
status line can be up to 5 minutes behind. Use this skill when the user wants the
current numbers immediately.

## Steps

1. Note the mtime of the two cache files, then run `~/.claude/scripts/usage-refresh.sh`
   with Bash. It refreshes both caches and prints nothing.
   - If that script does not exist, claude-statusline is not installed here. Say so and stop.
2. Read the caches:
   - Codex — `~/.claude/codex-status/codex-usage.json`: `rate_limit.primary_window.used_percent`
     (5-hour), `rate_limit.secondary_window.used_percent` (weekly),
     `rate_limit.primary_window.reset_at` (Unix epoch).
   - Claude — `~/.claude/codex-status/claude-usage.json`: `five_hour.used_percentage`,
     `seven_day.used_percentage`, `five_hour.resets_at` (Unix epoch), `fetched_at`.
3. A cache whose mtime did not change means one of two things — tell them apart by
   how old the file is:
   - Under a minute old: the poll was skipped on purpose, because the numbers were
     already current. Nothing is wrong.
   - Older than that: this half failed and its numbers are older than they look.
     Usual causes are Codex not being logged in (`~/.codex/auth.json` missing), the
     Claude usage endpoint rate-limiting the call (it answers bursts with 429 for a
     few minutes), or an OAuth token that expired before Claude Code rotated it.
     Report a stale half as stale rather than presenting old numbers as current.
4. Report the numbers in a line or two. The status line picks them up within its
   refresh interval (2s).
