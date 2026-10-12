#!/bin/bash
# Refreshes both usage caches. Bound to the `cu-refresh` command, used by the
# /refresh skill, and called by the status line's shared 5-minute trigger.
#
# $1 (optional): passed through to both scripts — how long, in seconds, numbers
# that Claude Code or Codex reported on its own count as current. The status
# line passes 300 so nothing is fetched while you are actively working. Manual
# runs omit it and fetch regardless, bar a one-minute burst guard on each cache.
#
# Each half is independent: one failing (not logged in, endpoint rate limited)
# leaves the other's cache updated and the previous values in place.
DIR="$HOME/.claude/scripts"

# The status line keeps the last line it drew per session (render.<session id>)
# to replay while nothing changes. A live session rewrites its file at least
# once a minute; sweep the ones left behind by sessions that are gone, and with
# them any temporary file a cancelled run did not get to rename.
find "$HOME/.claude/codex-status" -maxdepth 1 \( -name 'render.*' -o -name '*.tmp.*' \) -mmin +1440 -delete 2>/dev/null

[ -x "$DIR/codex-usage-refresh.sh" ] && "$DIR/codex-usage-refresh.sh" "$@"
[ -x "$DIR/claude-usage-refresh.sh" ] && "$DIR/claude-usage-refresh.sh" "$@"
exit 0
