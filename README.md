# claude-statusline

**English** · [한국어](README.ko.md)

A one-line status line for Claude Code: Claude and Codex usage, context
usage as a percentage, and the task in progress.

![statusline preview](assets/statusline.svg)

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/zoo3323/claude-statusline/main/install-claude-statusline.sh | bash
```

Restart Claude Code and the status line appears. `jq` is fetched into
`~/.local/bin` if it is missing, no admin rights required. Everything lands in
`~/.claude/scripts/`, a `/refresh` skill, caches under
`~/.claude/codex-status/`, and a `cu-refresh` link in `~/.local/bin`.

Claude Code re-runs the status line every second in every open session, and
nothing of it stays in memory in between. While nothing it shows has changed, a
session replays the line it drew last without starting a single other program,
the light included (3 to 4 ms a tick on an M-series Mac); a full render, needed
when a number changes, takes about 15 ms.

## Reading a usage gauge

| part | meaning |
| --- | --- |
| bar length | share of the 5-hour window still left |
| block height `▁▂▃▄▅▆▇█` | weekly quota still left |
| colour | yellow under 30% left, red under 10% |
| `↻1h23m` | time until the window resets |

The `ctx` gauge runs the other way: it fills up as the context does, yellow from
70% used and red from 90%.

A gauge whose quota is being spent right now shows it, in every session — the
quota is the account's, whichever session spends it. The `claude` gauge is in use
while any Claude Code session on this machine is at work, the `codex` gauge
while a Codex task is running. In the session that is itself at work a light
runs along the gauge, from right to left; in the others the end of the bar
glows, without moving.

Nothing moves in a session that is not at work, on purpose: a moving light is
terminal output every second (about 100 bytes), and a connection that keeps
terminal output for replay — Eternal Terminal holds it in the server's memory —
fills up on it. A session at work writes to the terminal all the time anyway.

The gauges are as wide as the terminal allows: wider in a wide one, narrower in a
narrow one, and where there is no room for a gauge only the numbers remain. The
task in progress takes what is left of the line and is cut to fit.

Usage keeps moving while you are idle — it is polled in the background, not only
after you prompt. To refresh on the spot: `cu-refresh` in a terminal, `/refresh`
inside Claude Code. The Codex gauge only appears when the Codex CLI is logged
in on this machine.

The poll reuses the OAuth tokens Claude Code and Codex already store on this
machine to read your account usage. Those are account-info requests: they
consume no usage, and nothing is sent anywhere else. Neither endpoint is a
documented API, so on any error the gauge falls back to what Claude Code
reports.

## Icons instead of the words

```bash
touch ~/.claude/codex-status/icons   # delete it to get the words back
```

From the next render on, the gauges are labelled with the OpenAI and Claude
logos instead of `codex` and `claude`, and `ctx` becomes a speech bubble. These
are Nerd Fonts glyphs, and a script cannot tell whether your terminal can draw
them — hence off by default. What counts is the font of the terminal you are
sitting at, also when Claude Code runs on another machine over SSH; the marker
file goes on the machine Claude Code runs on.

The bubble is in any Nerd Fonts 3 font. The two logos (`U+EC81`, `U+EC82`) exist
only since Nerd Fonts 3.5.0; installing *Symbols Nerd Font* 3.5 or later
provides them. A terminal that bundles an older copy may have to be pointed at
the installed one. Ghostty 1.3 bundles 3.4.0, so its config needs:

```
font-codepoint-map = U+EC81-U+EC82=Symbols Nerd Font
```

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/zoo3323/claude-statusline/main/uninstall-claude-statusline.sh | bash
```

Reverts exactly what the installer touched and leaves everything else alone.

## Development

The scripts live in `src/`. `install-claude-statusline.sh` is generated from them
by `./build.sh` — edit `src/`, not the installer. `./build.sh --check` fails when
the committed installer is out of date. `./test.sh` runs the scripts against a
throwaway home directory with the network stubbed out.
