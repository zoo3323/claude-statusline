#!/bin/bash
# Generates install-claude-statusline.sh from installer.template.sh and src/.
#
# The template carries one line per embedded file:
#   @@EMBED "$SCRIPTS_DIR/statusline-codex.sh" src/statusline-codex.sh
# which is replaced by a quoted heredoc writing that file verbatim, so the
# shipped installer stays a single self-contained file while the scripts
# themselves remain real, lintable, testable files in src/.
#
#   ./build.sh          regenerate the installer
#   ./build.sh --check   fail if the committed installer is out of date
set -euo pipefail

cd "$(dirname "$0")"
TEMPLATE=installer.template.sh
OUT=install-claude-statusline.sh
VERSION=$(tr -d '[:space:]' < VERSION)

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

while IFS= read -r line; do
  case "$line" in
    '@@EMBED '*)
      rest=${line#@@EMBED }
      src=${rest##* }
      dest=${rest% *}
      [ -f "$src" ] || { echo "build: missing source $src" >&2; exit 1; }
      tag="EMBEDDED_$(basename "$src")"
      if grep -qxF "$tag" "$src"; then
        echo "build: $src contains a line equal to its heredoc terminator ($tag)" >&2
        exit 1
      fi
      printf "cat > %s <<'%s'\n" "$dest" "$tag"
      cat "$src"
      printf '%s\n' "$tag"
      ;;
    *)
      printf '%s\n' "${line//@@VERSION@@/$VERSION}"
      ;;
  esac
done < "$TEMPLATE" > "$tmp"

bash -n "$tmp" || { echo "build: generated installer has a syntax error" >&2; exit 1; }

if [ "${1:-}" = "--check" ]; then
  if diff -q "$OUT" "$tmp" >/dev/null 2>&1; then
    echo "up to date: $OUT matches installer.template.sh + src/"
  else
    echo "stale: $OUT does not match installer.template.sh + src/ — run ./build.sh" >&2
    diff -u "$OUT" "$tmp" | head -40 >&2
    exit 1
  fi
else
  chmod +x "$tmp"
  cp "$tmp" "$OUT"
  chmod +x "$OUT"
  echo "built $OUT (version $VERSION, $(wc -l < "$OUT" | tr -d ' ') lines)"
fi
