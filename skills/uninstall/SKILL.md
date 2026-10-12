---
name: uninstall
description: Remove the claude-statusline status line — its scripts, its caches and the statusLine entry in settings.json. The plugin itself stays until it is uninstalled with /plugin.
disable-model-invocation: true
---

# Remove the status line

This undoes what `/usage-statusline:setup` did. It does not uninstall the plugin.

1. Tell the user what will be removed and ask them to confirm:
   - the scripts in `~/.claude/scripts/` (`statusline-codex.sh`, `usage-refresh.sh`,
     `claude-usage-refresh.sh`, `codex-usage-refresh.sh`)
   - the caches and the saved choices in `~/.claude/codex-status/`
   - the `cu-refresh` link in `~/.local/bin`
   - the `statusLine` entry in `~/.claude/settings.json`, when it is this status line
2. Once they confirm, run:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/uninstall-claude-statusline.sh"
   ```

   It backs up `settings.json` first, leaves every other setting alone, and prints what
   it did. If it fails, show its output.
3. Say that the line disappears in a new session, and that the plugin itself is removed
   with `/plugin uninstall usage-statusline` if they no longer want the skills either.
