#!/bin/bash
# Installer for the Claude Code status line.
#   curl -fsSL https://raw.githubusercontent.com/zoo3323/usage-statusline/main/install.sh | bash
# Options go after `bash -s --`; see usage() below. The plugin's setup skill runs
# this same file.
#
# GENERATED FILE — do not edit. The scripts it writes live in src/; change them
# there and run ./build.sh.
#
# Everything is defined as functions and only run by the `main "$@"` on the last
# line. A download cut short therefore installs nothing at all instead of
# leaving a truncated script behind.
set -e

VERSION="@@VERSION@@"

CLAUDE_DIR="$HOME/.claude"
SCRIPTS_DIR="$CLAUDE_DIR/scripts"
STATE_DIR="$CLAUDE_DIR/codex-status"
SKILLS_DIR="$CLAUDE_DIR/skills/refresh"
SETTINGS="$CLAUDE_DIR/settings.json"
LOCAL_BIN="$HOME/.local/bin"

usage() {
  cat <<'EOF'
Usage: install.sh [options]

What the status line shows (kept from the last time when left out):
  --show "<segments>"   any of: folder model codex claude ctx
  --countdown on|off    the time until a usage window resets
  --icons on|off        icons instead of the words codex, claude and ctx
                        (the terminal's font needs Nerd Fonts 3.5 glyphs)
  --light on|off        the light and the glow on a quota that is in use

  --plugin              run from the Claude Code plugin: leave the stand-alone
                        /refresh skill out, the plugin brings its own
  --sync                only bring an existing installation up to this version;
                        installs nothing new and leaves settings.json alone
EOF
}

PLUGIN=""; SYNC=""; OPT_SHOW=""; OPT_COUNTDOWN=""; OPT_ICONS=""; OPT_LIGHT=""
parse_args() {
  local s
  while [ $# -gt 0 ]; do
    case "$1" in
      --show)
        OPT_SHOW=$2
        [ -n "$OPT_SHOW" ] || { echo "❌ --show needs at least one segment"; return 2; }
        for s in $OPT_SHOW; do
          case "$s" in folder|model|codex|claude|ctx) ;;
            *) echo "❌ --show: unknown segment '$s'"; return 2 ;;
          esac
        done
        shift ;;
      --countdown|--icons|--light)
        case "$2" in on|off) ;; *) echo "❌ $1 takes on or off"; return 2 ;; esac
        case "$1" in --countdown) OPT_COUNTDOWN=$2 ;; --icons) OPT_ICONS=$2 ;; --light) OPT_LIGHT=$2 ;; esac
        shift ;;
      --plugin) PLUGIN=1 ;;
      --sync)   SYNC=1 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "❌ Unknown option: $1"; usage; return 2 ;;
    esac
    shift
  done
}

verify_sha256() { # $1=file $2=expected hex digest
  local got
  if command -v shasum >/dev/null 2>&1; then
    got=$(shasum -a 256 "$1" | awk '{print $1}')
  elif command -v sha256sum >/dev/null 2>&1; then
    got=$(sha256sum "$1" | awk '{print $1}')
  else
    echo "⚠️  Neither shasum nor sha256sum found — skipping checksum verification."
    return 0
  fi
  [ "$got" = "$2" ]
}

# jq is required. Fetch it into ~/.local/bin when it is missing, so no admin
# rights and no package manager are needed. Digests are the ones published in
# the jq 1.7.1 release's own sha256sum.txt.
ensure_jq() {
  if command -v jq >/dev/null 2>&1; then
    return 0
  fi
  echo "ℹ️  jq not found — installing it locally (no admin rights required)..."
  local ver="jq-1.7.1" asset sum tmp
  case "$(uname -s)/$(uname -m)" in
    Darwin/arm64)
      asset="jq-macos-arm64"; sum="0bbe619e663e0de2c550be2fe0d240d076799d6f8a652b70fa04aea8a8362e8a" ;;
    Darwin/*)
      asset="jq-macos-amd64"; sum="4155822bbf5ea90f5c79cf254665975eb4274d426d0709770c21774de5407443" ;;
    Linux/aarch64|Linux/arm64)
      asset="jq-linux-arm64"; sum="4dd2d8a0661df0b22f1bb9a1f9830f06b6f3b8f7d91211a1ef5d7c4f06a8b4a5" ;;
    Linux/*)
      asset="jq-linux-amd64"; sum="5942c9b0934e510ee61eb3e30273f1b3fe2590df93933a93d7c58b81d19c8ff5" ;;
    *)
      echo "❌ No automatic install for this OS. Install jq yourself and run this again."
      return 1 ;;
  esac
  mkdir -p "$LOCAL_BIN"
  tmp="$LOCAL_BIN/.jq.download.$$"
  if ! curl -fsSL -o "$tmp" "https://github.com/jqlang/jq/releases/download/${ver}/${asset}"; then
    rm -f "$tmp"
    echo "❌ Could not download jq. Install it manually and run this again: (mac) brew install jq / (ubuntu) sudo apt install -y jq"
    return 1
  fi
  if ! verify_sha256 "$tmp" "$sum"; then
    rm -f "$tmp"
    echo "❌ The downloaded jq does not match its published checksum — refusing to install it."
    return 1
  fi
  chmod +x "$tmp"
  mv "$tmp" "$LOCAL_BIN/jq"
  export PATH="$LOCAL_BIN:$PATH"
  command -v jq >/dev/null 2>&1 || { echo "❌ jq is installed but still not on PATH."; return 1; }
  echo "✅ Installed jq to $LOCAL_BIN/jq"
}

# Put ~/.local/bin on PATH in shell rc files that lack it, so the next shell finds
# jq and cu-refresh. The pattern looks for a line that actually sets PATH, not a
# comment that happens to mention the directory.
ensure_local_bin_on_path() {
  local rc
  for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [ -f "$rc" ] || continue
    if ! grep -qE '^[[:space:]]*[^#[:space:]].*PATH.*\.local/bin' "$rc"; then
      printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
    fi
  done
}

write_files() {
@@EMBED "$SCRIPTS_DIR/statusline-codex.sh" src/statusline-codex.sh
chmod +x "$SCRIPTS_DIR/statusline-codex.sh"

@@EMBED "$SCRIPTS_DIR/codex-usage-refresh.sh" src/codex-usage-refresh.sh
chmod +x "$SCRIPTS_DIR/codex-usage-refresh.sh"

@@EMBED "$SCRIPTS_DIR/claude-usage-refresh.sh" src/claude-usage-refresh.sh
chmod +x "$SCRIPTS_DIR/claude-usage-refresh.sh"

@@EMBED "$SCRIPTS_DIR/usage-refresh.sh" src/usage-refresh.sh
chmod +x "$SCRIPTS_DIR/usage-refresh.sh"

# refresh skill, so /refresh works from any session (the plugin has its own)
if [ -z "$PLUGIN" ]; then
mkdir -p "$SKILLS_DIR"
@@EMBED "$SKILLS_DIR/SKILL.md" skills/refresh/SKILL.md
fi
}

# What the status line shows — ~/.claude/codex-status/config, see "What to draw"
# in statusline-codex.sh. The file is only written when there is a choice to
# record: an option given here, or the marker file with which 1.2 switched the
# icons on, which this file replaces.
write_config() {
  local cfg="$STATE_DIR/config" show="" countdown="" icons="" light="" k v write=""
  if [ -f "$cfg" ]; then
    while IFS='=' read -r k v || [ -n "$k" ]; do
      case "$k" in show) show=$v ;; countdown) countdown=$v ;; icons) icons=$v ;; light) light=$v ;; esac
    done < "$cfg"
  fi
  if [ -e "$STATE_DIR/icons" ]; then
    [ -n "$icons" ] || icons=on
    rm -f "$STATE_DIR/icons"; write=1
  fi
  [ -n "$OPT_SHOW" ] && { show=$OPT_SHOW; write=1; }
  [ -n "$OPT_COUNTDOWN" ] && { countdown=$OPT_COUNTDOWN; write=1; }
  [ -n "$OPT_ICONS" ] && { icons=$OPT_ICONS; write=1; }
  [ -n "$OPT_LIGHT" ] && { light=$OPT_LIGHT; write=1; }
  # (up to 1.4 there was a sixth segment, the task in progress)
  case " $show " in *" task "*)
    show=" $show "; show=${show/ task / }; show=${show# }; show=${show% }; write=1 ;;
  esac
  [ -n "$write" ] || return 0
  printf 'show=%s\ncountdown=%s\nicons=%s\nlight=%s\n' \
    "${show:-folder model codex claude ctx}" "${countdown:-on}" "${icons:-off}" "${light:-on}" > "$cfg.tmp.$$" \
    && mv "$cfg.tmp.$$" "$cfg"
}

newer_version() { # is $1 a later version than $2?
  local a b i
  IFS=. read -r -a a <<< "$1"
  IFS=. read -r -a b <<< "$2"
  for i in 0 1 2; do
    [ "${a[i]:-0}" -gt "${b[i]:-0}" ] 2>/dev/null && return 0
    [ "${a[i]:-0}" -lt "${b[i]:-0}" ] 2>/dev/null && return 1
  done
  return 1
}

# --sync, which the plugin runs when a session starts: an installation the setup
# skill made follows the plugin's version. Where nothing was set up, nothing is.
sync_installed() {
  local have
  [ -f "$STATE_DIR/installed-version" ] || return 0
  have=$(cat "$STATE_DIR/installed-version")
  newer_version "$VERSION" "$have" || return 0
  write_files
  link_cu_refresh
  write_config
  remove_legacy_files
  printf '%s\n' "$VERSION" > "$STATE_DIR/installed-version"
}

# cu-refresh as a symlink on PATH instead of a shell alias, so no rc file has to
# be rewritten. Versions before 1.0.0 appended an alias; remove it when it is
# there, otherwise the alias would shadow the symlink forever.
link_cu_refresh() {
  local rc
  mkdir -p "$LOCAL_BIN"
  ln -sf "$SCRIPTS_DIR/usage-refresh.sh" "$LOCAL_BIN/cu-refresh"
  for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [ -f "$rc" ] || continue
    if grep -q 'alias cu-refresh=' "$rc"; then
      # The last pattern is the localized comment line shipped by earlier versions.
      sed -i.bak '/alias cu-refresh=/d; /# Refresh both usage gauges now/d; /# Codex 사용량 즉시 새로고침/d' "$rc"
      rm -f "$rc.bak"
    fi
  done
}

# Keep the three most recent settings backups; installs and uninstalls each add
# one and nothing else ever cleans them up.
prune_settings_backups() {
  local old
  old=$(ls -t "$SETTINGS".bak.* 2>/dev/null | tail -n +4) || true
  [ -n "$old" ] && printf '%s\n' "$old" | xargs rm -f
  return 0
}

# Merge the statusLine into settings.json (existing settings are preserved; a
# timestamped backup is written first). It is re-run every second: that is the
# pace of the lights on a gauge in use, and a session in which nothing changed
# answers such a tick by replaying its last line, without spawning anything. Versions before 1.1.0 also registered
# Codex in-flight hooks for a run-state segment the status line no longer
# draws — strip those on upgrade, the hook script is gone.
merge_settings() {
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
  prune_settings_backups
  jq '
    .statusLine = {type: "command", command: "~/.claude/scripts/statusline-codex.sh", refreshInterval: 1}
    | (if .hooks then
         .hooks |= with_entries(.value |= map(select(.matcher != "mcp__codex__codex|mcp__codex__codex-reply")))
       else . end)
  ' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
}

# Leftovers from earlier versions: the hook script and its per-session
# counter/lock files (before 1.1.0), the per-session payload dumps the very
# first status line wrote on every render (*.state.json), and the session-log
# cache in the format used before 1.2.0.
remove_legacy_files() {
  rm -f "$SCRIPTS_DIR/codex-status-set.sh" "$STATE_DIR"/*.count \
        "$STATE_DIR"/claude-usage.last "$STATE_DIR"/codex-usage.last \
        "$STATE_DIR"/*.state.json "$STATE_DIR"/codex-sess.cache
  rm -rf "$STATE_DIR"/*.lock
}

main() {
  parse_args "$@" || exit 2
  if [ -n "$SYNC" ]; then
    sync_installed
    return 0
  fi
  mkdir -p "$SCRIPTS_DIR" "$STATE_DIR"
  ensure_jq
  ensure_local_bin_on_path
  write_files
  link_cu_refresh
  merge_settings
  write_config
  remove_legacy_files
  printf '%s\n' "$VERSION" > "$STATE_DIR/installed-version"

  echo "✅ Installed usage-statusline $VERSION"
  echo "   - Status line: it appears at the bottom, in a new session at the latest"
  if [ -n "$PLUGIN" ]; then
    echo "   - Refresh usage now: cu-refresh in a terminal, /usage-statusline:refresh inside Claude Code"
    echo "   - Change what it shows: /usage-statusline:setup"
  else
    echo "   - Refresh usage now: cu-refresh in a terminal, /refresh inside Claude Code"
    echo "   - Change what it shows: run this again with options, see --help"
  fi
  echo "   - Backup: $SETTINGS.bak.*"
}

main "$@"
