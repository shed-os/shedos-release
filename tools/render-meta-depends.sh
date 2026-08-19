#!/usr/bin/env bash
# render-meta-depends.sh; regenerate packaging/shedos-meta/PKGBUILD.
#
# Source of truth:
#   release-manifest.toml         → the release this metapackage is, and every
#                                   ShedOS package it installs, at the exact
#                                   version the channel serves. The names come
#                                   from the manifest rather than from a list
#                                   kept here, so a package reaches a fresh
#                                   install because the release says it is part
#                                   of the release.
#   packages/.meta-closure.txt    → fully-resolved Arch transitive closure
#                                   (from sudo tools/resolve-meta-closure.sh).
#                                   Every transitive Arch dep is listed
#                                   explicitly so install-time pacstrap has
#                                   no virtual-provider rolls left to make.
#   packages/aur.txt              → AUR deps the ISO pacstrap installs
#   packages/aur-norepublish.txt  → subset of aur.txt we are not allowed to
#                                   redistribute under the ShedOS key (EULA).
#                                   Moved from depends= to optdepends= so
#                                   they stay visible on the metapackage.
#                                   They ship with the ISO unsigned; users
#                                   reinstall via `shedman install` (yay).
#   packages/installer-only.txt   → packages bundled into the ISO for
#                                   install-time use only. Excluded from
#                                   both depends= and optdepends= so they
#                                   never reach the installed system via
#                                   shedos-meta (calamares, the installer).
#   packages/meta-conflicts.txt   → concrete providers of virtuals we do not
#                                   ship, emitted as conflicts=().
#
# Output: packaging/shedos-meta/PKGBUILD with a fresh depends=() +
# optdepends=().
#
# Run this whenever the manifest, packages/.meta-closure.txt or
# packages/aur.txt changes. The generated PKGBUILD is committed so a build
# works without re-running the script first. Regenerate the closure first
# whenever packages/official/*.txt changes.

set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=tools/lib-meta.sh
source "$here/lib-meta.sh"
out=$META_PKGBUILD

if [[ ! -f $META_CLOSURE ]]; then
    echo "ERROR: $META_CLOSURE missing." >&2
    echo "       Run: sudo tools/resolve-meta-closure.sh" >&2
    exit 1
fi
# Each list is read into a variable before it is used, because a list read
# through a process substitution takes its failure with it: a missing
# aur-norepublish.txt would come back as no names at all and quietly turn ten
# packages we may not redistribute into hard dependencies.
closure_raw=$(list_names "$META_CLOSURE") || exit 1
aur_raw=$(list_names "$META_PACKAGES/aur.txt") || exit 1
norepublish_raw=$(list_names "$META_PACKAGES/aur-norepublish.txt") || exit 1
installer_raw=$(list_names "$META_PACKAGES/installer-only.txt") || exit 1
conflicts_raw=$(list_names "$META_CONFLICTS") || exit 1

# LC_ALL=C on every sort, because the order these produce is the order the
# generated PKGBUILD ships and a collation is not the same everywhere: en_US
# ignores the punctuation and puts atk before at-spi2-core, C does the
# opposite. Without it the file a desk renders and the file CI renders differ
# by a reordering, and the committed one stops being reproducible depending on
# who ran the script.
mapfile -t official < <(cut -f1 <<<"$closure_raw" | LC_ALL=C sort -u)
mapfile -t replaced < <(awk -F'\t' '$2 == "replaced" { print $1 }' <<<"$closure_raw" \
    | LC_ALL=C sort -u)
mapfile -t aur < <(LC_ALL=C sort -u <<<"$aur_raw")
[[ -n $conflicts_raw ]] \
    || { echo "ERROR: $META_CONFLICTS names nothing." >&2; exit 1; }
mapfile -t conflicts <<<"$conflicts_raw"

# Associative sets of the two exclusion lists, for O(1) lookup.
declare -A norepublish=()
for p in $norepublish_raw; do norepublish[$p]=1; done

# Installer-only packages; bundled into the ISO but excluded from
# shedos-meta entirely (neither depends nor optdepends).
declare -A installer_only=()
for p in $installer_raw; do installer_only[$p]=1; done

# The ShedOS packages, from the release manifest, pinned to the exact release
# the channel serves. This is what makes a ShedOS install internally
# consistent by construction: a metapackage naming bare package names installs
# whatever mixture the channel happens to hold at that moment, and the
# half-update the single shedos-hyprland version floor was written for is the
# general case of that.
#
# The manifest names this package too, from the release it was published into,
# and a package may not depend on itself: pacman takes it, and the first pkgrel
# bump after a render then ships a metapackage pinning its own name at the
# version before it, which nothing in the channel can satisfy.
shedos_pkgs=()
declare -A shedos_names=()
while IFS=$'\t' read -r name pkgver pkgrel; do
    [[ -n $name ]] || continue
    shedos_names[$name]=1
    [[ $name == "$META_PKGNAME" ]] && continue
    [[ -n ${installer_only[$name]:-} ]] && continue
    shedos_pkgs+=("$name=$pkgver-$pkgrel")
done < <(manifest_entries "$META_MANIFEST")
(( ${#shedos_pkgs[@]} > 0 )) || { echo "ERROR: $META_MANIFEST names no packages." >&2; exit 1; }

version=$(manifest_version "$META_MANIFEST")
[[ -n $version ]] || { echo "ERROR: $META_MANIFEST names no release version." >&2; exit 1; }

# A name Arch and the channel both carry has to be written down as replaced,
# and a name written down as replaced has to be one the channel carries.
# Either half missing means the closure and the manifest have drifted apart,
# and the metapackage would then either name the Arch package or name nothing
# — both silently.
declare -A is_replaced=()
for p in "${replaced[@]}"; do
    [[ -n $p ]] || continue
    is_replaced[$p]=1
    [[ -n ${shedos_names[$p]:-} ]] \
        || { echo "ERROR: the closure marks $p replaced and the manifest does not name it." >&2; exit 1; }
done
for p in "${official[@]}"; do
    [[ -n ${shedos_names[$p]:-} ]] || continue
    [[ -n ${is_replaced[$p]:-} ]] \
        || { echo "ERROR: $p is in the closure and the manifest and is not marked replaced." >&2; exit 1; }
done

# Installer-only entries are dropped before the depends/optdepends split, and
# a name the channel replaces is dropped from the Arch side because the pinned
# form above already carries it.
# Everything else: republishable → depends=, proprietary AUR → optdepends=.
declare -A seen
ordered=("${shedos_pkgs[@]}")
optional=()
for p in "${official[@]}" "${aur[@]}"; do
    [[ -z $p ]] && continue
    [[ -n ${seen[$p]:-} ]] && continue
    seen[$p]=1
    [[ -n ${installer_only[$p]:-} ]] && continue
    [[ -n ${is_replaced[$p]:-} ]] && continue
    if [[ -n ${norepublish[$p]:-} ]]; then
        optional+=("$p")
    else
        ordered+=("$p")
    fi
done

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

# Preserve the current pkgrel if shedos-meta already exists and pkgver
# matches; that way re-running this script after a manifest change that does
# not move the release does not reset pkgrel to 1.
pkgrel=1
if [[ -f "$out" ]]; then
    existing_ver=$(awk -F= '/^pkgver=/ {print $2; exit}' "$out" 2>/dev/null || true)
    existing_rel=$(awk -F= '/^pkgrel=/ {print $2; exit}' "$out" 2>/dev/null || true)
    if [[ "$existing_ver" == "$version" && -n "$existing_rel" ]]; then
        pkgrel=$existing_rel
    fi
fi

{
    cat <<EOF
# Maintainer: ShedOS <https://github.com/shed-os>
#
# AUTO-GENERATED by tools/render-meta-depends.sh; do not edit by hand.
# After editing packages/official/*.txt: sudo tools/resolve-meta-closure.sh
# (regenerates packages/.meta-closure.txt), then re-run this script.
# Editing packages/aur.txt only: just re-run this script.
# pkgver is the release release-manifest.toml defines, and every ShedOS
# package below is pinned to the version that manifest names.
#
# Zero-file metapackage. Pulls in every ShedOS package plus every Arch / AUR
# package a default ShedOS install needs. This is the source of truth for
# "what's on a fresh install".

pkgname=$META_PKGNAME
pkgver=$version
pkgrel=$pkgrel
pkgdesc='ShedOS meta-package — installs the full default ShedOS environment'
arch=('any')
url='https://github.com/shed-os/shedos-release'
license=('GPL-3.0-or-later')
depends=(
EOF
    for p in "${ordered[@]}"; do
        printf "    '%s'\n" "$p"
    done
    cat <<'EOF'
)
optdepends=(
EOF
    for p in "${optional[@]}"; do
        printf "    '%s: proprietary AUR package; reinstall via shedman install'\n" "$p"
    done
    cat <<'EOF'
)
conflicts=(
EOF
    for p in "${conflicts[@]}"; do
        printf "    '%s'\n" "$p"
    done
    cat <<'EOF'
)

package() {
    # Intentionally empty; this is a metapackage.
    :
}
EOF
} > "$tmp"

install -Dm644 "$tmp" "$out"

echo "Wrote $out ($(wc -l < "$tmp") lines, ${#ordered[@]} deps, ${#optional[@]} optdeps, ${#conflicts[@]} conflicts)"
