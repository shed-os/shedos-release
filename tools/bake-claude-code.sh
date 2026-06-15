#!/usr/bin/env bash
# Place a pinned Claude Code native binary into a skel tree:
#   <skel>/.local/share/claude/versions/<ver>   the binary (a single ELF)
#   <skel>/.local/bin/claude -> ../share/claude/versions/<ver>
# Mirrors the official installer's download + sha256 check, minus its
# launcher step (which writes an absolute symlink and ignores $HOME).
set -euo pipefail

ver=${1:?usage: bake-claude-code.sh <version> <skel-dir>}
skel=${2:?usage: bake-claude-code.sh <version> <skel-dir>}
base=https://downloads.claude.ai/claude-code-releases
platform=linux-x64   # the ISO airootfs is glibc x86_64

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

want=$(curl -fsSL "$base/$ver/manifest.json" | tr -d '\n\r\t' | sed 's/ \+/ /g' \
    | grep -oE "\"$platform\"[^}]*\"checksum\"[[:space:]]*:[[:space:]]*\"[a-f0-9]{64}\"" \
    | grep -oE '[a-f0-9]{64}' | head -1)
[[ -n $want ]] || { echo "bake-claude-code: no $platform checksum in $ver manifest" >&2; exit 1; }

curl -fsSL -o "$tmp/claude" "$base/$ver/$platform/claude"
got=$(sha256sum "$tmp/claude" | cut -d' ' -f1)
[[ $got == "$want" ]] || { echo "bake-claude-code: checksum mismatch (got $got, want $want)" >&2; exit 1; }

install -Dm755 "$tmp/claude" "$skel/.local/share/claude/versions/$ver"
mkdir -p "$skel/.local/bin"
ln -sfn "../share/claude/versions/$ver" "$skel/.local/bin/claude"
echo "bake-claude-code: $ver into $skel"
