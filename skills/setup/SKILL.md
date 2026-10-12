---
name: setup
description: Turn on the usage-statusline status line and choose what it shows — folder, model, Claude and Codex usage gauges, context, countdowns, the in-use light. Run it again to change the choice.
disable-model-invocation: true
---

# Set up the status line

The status line is a script Claude Code runs for the bottom line of the screen. A
plugin cannot switch a status line on by itself, so this skill does it: it copies
the scripts to `~/.claude/scripts/`, records what the user wants to see, and points
`statusLine` in `~/.claude/settings.json` at the script.

Talk to the user in their language. The option labels below are in English; translate
them.

## 1. Look at what is there

- Read `~/.claude/settings.json` if it exists. If `statusLine.command` is set and does
  not contain `statusline-codex.sh`, the user already has a different status line.
  Tell them which command it is and ask whether to replace it. Stop if they decline:
  nothing has been changed.
- Read `~/.claude/codex-status/config` if it exists. It holds the current choice, one
  `key=value` a line (`show=`, `countdown=`, `icons=`, `light=`). Offer the current
  values as the starting point. Without the file everything is shown.

## 2. Ask what to show

Ask both in one AskUserQuestion call. Where that tool is not available, ask the
same in plain text and wait for the answer.

1. **Session** (several can be chosen): Folder name · Model and effort · Context gauge
2. **Usage** (several can be chosen): Claude usage gauge · Codex usage gauge · Time until
   a window resets · In-use light

Say with the questions, briefly, that the Codex gauge only appears on a machine where
the Codex CLI is logged in.

The gauges are labelled with icons (the OpenAI and Claude logos and a speech bubble).
That is not a question: do not offer words instead.

At least one of the five segments (folder, model, context, Claude gauge, Codex gauge)
has to be chosen. If none is, say so and ask again.

## 3. Apply

Turn the answers into three values:

- `show`: the chosen segments out of `folder model codex claude ctx`, in that order
- `countdown`: `on` if "Time until a window resets" was chosen, else `off`
- `light`: `on` if "In-use light" was chosen, else `off`

Then run, with the values filled in:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/install.sh" --plugin --show "folder model codex claude ctx" --countdown on --icons on --light on
```

The script fetches `jq` into `~/.local/bin` if it is missing, backs up `settings.json`
before changing it, and prints what it did. If it fails, show its output and stop.

## 4. Report

In a few lines: what is shown now, and that the line appears at the bottom within a
couple of seconds — in a new session at the latest. To change the choice, run
`/usage-statusline:setup` again. `/usage-statusline:refresh` fetches the usage numbers
on the spot, `/usage-statusline:uninstall` removes everything this skill set up.

Add that the icons need a terminal font with Nerd Fonts 3.5 glyphs — without one they
show as empty boxes — and the one line Ghostty needs, from the "Your choice" section of
the plugin's README (`${CLAUDE_PLUGIN_ROOT}/README.md`).
