#!/bin/bash
# Refreshes both usage caches. Bound to the `cu-refresh` shell alias, used by
# the /refresh skill, and called by the status line's shared 5-minute trigger.
#
# $1 (optional): freshness bound in seconds, passed through to both scripts —
# each one skips its network call when it already has a source younger than
# this. Manual runs omit it (the scripts default to a short burst guard), the
# status line passes 300 so nothing is fetched while you are actively working.
#
# Each half is independent: one failing (not logged in, endpoint rate limited)
# leaves the other's cache updated and the previous values in place.
DIR="$HOME/.claude/scripts"
[ -x "$DIR/codex-usage-refresh.sh" ] && "$DIR/codex-usage-refresh.sh" "$@"
[ -x "$DIR/claude-usage-refresh.sh" ] && "$DIR/claude-usage-refresh.sh" "$@"
exit 0
