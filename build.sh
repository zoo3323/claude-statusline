#!/bin/bash
# Generates install.sh from installer.template.sh and src/.
#
# The template carries one line per embedded file:
#   @@EMBED "$SCRIPTS_DIR/statusline-codex.sh" src/statusline-codex.sh
# which is replaced by a quoted heredoc writing that file verbatim, so the
# shipped installer stays a single self-contained file while the scripts
# themselves remain real, lintable, testable files in src/.
#
# The plugin manifest carries the version too; it is stamped from VERSION here so
# that the two cannot drift apart.
#
#   ./build.sh          regenerate the installer, stamp the plugin manifest
#   ./build.sh --check   fail if either is out of date
set -euo pipefail

cd "$(dirname "$0")"
TEMPLATE=installer.template.sh
OUT=install.sh
MANIFEST=.claude-plugin/plugin.json
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

manifest_version=$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$MANIFEST")

if [ "${1:-}" = "--check" ]; then
  if [ "$manifest_version" != "$VERSION" ]; then
    echo "stale: $MANIFEST says $manifest_version, VERSION says $VERSION — run ./build.sh" >&2
    exit 1
  fi
  if diff -q "$OUT" "$tmp" >/dev/null 2>&1; then
    echo "up to date: $OUT matches installer.template.sh + src/"
  else
    echo "stale: $OUT does not match installer.template.sh + src/ — run ./build.sh" >&2
    diff -u "$OUT" "$tmp" | head -40 >&2
    exit 1
  fi
else
  if [ "$manifest_version" != "$VERSION" ]; then
    sed "s/^\( *\"version\": *\"\)[^\"]*\"/\1$VERSION\"/" "$MANIFEST" > "$tmp.manifest" && mv "$tmp.manifest" "$MANIFEST"
  fi
  chmod +x "$tmp"
  cp "$tmp" "$OUT"
  chmod +x "$OUT"
  echo "built $OUT (version $VERSION, $(wc -l < "$OUT" | tr -d ' ') lines)"
fi
