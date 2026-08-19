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

# Committed sha256 pins are the trust anchor: the manifest ships over the same
# TLS channel as the binary, so a single compromised endpoint could serve a
# matching binary+manifest pair. Verifying against a hash recorded here (in git)
# instead means a swapped binary fails the build. Record the hash when bumping
# the version in the Makefile; sha256sum the downloaded ELF to obtain it.
declare -A pins=(
    [2.1.170]=849e007277a0442ab27570d3e3d6d43787507946590e8dd1947e5a39b7081f9e
)
want=${pins[$ver]:-}
[[ -n $want ]] || {
    echo "bake-claude-code: no pinned sha256 for $ver; add it to scripts/bake-claude-code.sh" >&2
    exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

curl -fsSL -o "$tmp/claude" "$base/$ver/$platform/claude"
got=$(sha256sum "$tmp/claude" | cut -d' ' -f1)
[[ $got == "$want" ]] || { echo "bake-claude-code: checksum mismatch (got $got, want $want)" >&2; exit 1; }

# Cross-check the manifest against the pin so an upstream that disagrees with
# the committed hash is surfaced, not silently trusted.
adv=$(curl -fsSL "$base/$ver/manifest.json" | tr -d '\n\r\t' | sed 's/ \+/ /g' \
    | grep -oE "\"$platform\"[^}]*\"checksum\"[[:space:]]*:[[:space:]]*\"[a-f0-9]{64}\"" \
    | grep -oE '[a-f0-9]{64}' | head -1)
[[ -z $adv || $adv == "$want" ]] || {
    echo "bake-claude-code: manifest checksum $adv disagrees with pin $want" >&2
    exit 1
}

install -Dm755 "$tmp/claude" "$skel/.local/share/claude/versions/$ver"
mkdir -p "$skel/.local/bin"
ln -sfn "../share/claude/versions/$ver" "$skel/.local/bin/claude"
echo "bake-claude-code: $ver into $skel"
