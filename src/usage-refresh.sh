#!/bin/bash
# Refreshes both usage caches right now, bypassing the status line's 5-minute
# schedule. Bound to the `cu-refresh` shell alias and used by the /refresh skill.
# Each half is independent: one failing (not logged in, endpoint rate limited)
# leaves the other's cache updated and the previous values in place.
DIR="$HOME/.claude/scripts"
[ -x "$DIR/codex-usage-refresh.sh" ] && "$DIR/codex-usage-refresh.sh"
[ -x "$DIR/claude-usage-refresh.sh" ] && "$DIR/claude-usage-refresh.sh"
exit 0
