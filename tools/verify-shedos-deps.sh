#!/usr/bin/env bash
# verify-shedos-deps.sh <package-dir> [<release-manifest.toml>]
#
# Pre-flight over the release's own packages: every dependency they declare has
# something that can satisfy it, and none of them pins an Arch package to an
# exact version. Both answers come in a fraction of a second, where the same
# two mistakes surface fifty minutes into a pacstrap.
#
# The depends are read out of the published packages' .PKGINFO rather than out
# of PKGBUILDs, because the PKGBUILDs are in fourteen other repositories now
# and what a release ships is what it ships.
#
# A dependency is satisfied when the release names it, when a source list names
# it, or when Arch serves it. The third leg is not slack: the installer's
# dependencies are deliberately outside the metapackage closure — nothing on an
# installed system should pull Calamares in — and they still have to be on the
# ISO, where pacstrap resolves them out of the frozen Arch databases.
#
# SHEDOS_ARCH_NAMES names a file of Arch package names in place of syncing a
# database, which is how this runs without root or a network.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(dirname "$HERE")
# shellcheck source=tools/lib-manifest.sh
source "$HERE/lib-manifest.sh"

(( $# >= 1 )) || { echo 'usage: verify-shedos-deps.sh <package-dir> [<manifest>]' >&2; exit 2; }
pkgdir=$1
manifest=${2:-$ROOT/release-manifest.toml}
[[ -d $pkgdir ]] || { echo "verify-shedos-deps: $pkgdir does not exist" >&2; exit 2; }
[[ -f $manifest ]] || { echo "verify-shedos-deps: $manifest does not exist" >&2; exit 2; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

manifest_read "$manifest" > "$WORK/manifest.tsv"
awk -F'\t' '$1 == "package" { print $2 }' "$WORK/manifest.tsv" \
    | LC_ALL=C sort -u > "$WORK/release.txt"

# Pulled in by base on every install; a source list has never had to name them.
printf '%s\n' bash coreutils diffutils gcc-libs glibc systemd \
    | LC_ALL=C sort -u > "$WORK/base.txt"

{
    for f in "$ROOT"/packages/official/*.txt "$ROOT"/packages/aur.txt \
             "$ROOT"/packages/.meta-closure.txt; do
        [[ -r $f ]] || continue
        awk 'NF' "$f"
    done
} | grep -v '^[[:space:]]*#' | awk '{ print $1 }' | LC_ALL=C sort -u > "$WORK/lists.txt"

# The name a source list uses where it is not the name a package depends on.
declare -A VIRTUAL_PROVIDERS=(
    [ananicy-cpp]=ananicy-cpp-git    # the -git build is the one that takes glibc 2.41+
)

if [[ -n ${SHEDOS_ARCH_NAMES:-} ]]; then
    LC_ALL=C sort -u "$SHEDOS_ARCH_NAMES" > "$WORK/arch.txt"
else
    [[ $EUID -eq 0 ]] || {
        echo 'verify-shedos-deps: needs root to sync a database, or SHEDOS_ARCH_NAMES' >&2
        exit 2
    }
    mkdir -p "$WORK/db"
    cat > "$WORK/pacman.conf" << 'EOF'
[options]
HoldPkg     = pacman glibc
Architecture = x86_64
SigLevel    = Never

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
    pacman -Sy --noconfirm --dbpath "$WORK/db" --config "$WORK/pacman.conf" > /dev/null
    # Names and what they provide both count: a dependency on a virtual is
    # satisfied by whatever declares it.
    pacman -Sl --dbpath "$WORK/db" --config "$WORK/pacman.conf" | awk '{ print $2 }' \
        > "$WORK/arch.raw"
    pacman -Si --dbpath "$WORK/db" --config "$WORK/pacman.conf" 2> /dev/null \
        | awk -F': *' '/^Provides/ { gsub(/[<>=][^ ]*/, "", $2); print $2 }' \
        | tr ' ' '\n' >> "$WORK/arch.raw"
    grep -v '^$\|^None$' "$WORK/arch.raw" | LC_ALL=C sort -u > "$WORK/arch.txt"
fi

covered() {
    local dep=$1 lookup=${VIRTUAL_PROVIDERS[$1]:-$1}
    grep -qxF "$dep" "$WORK/release.txt" && return 0
    grep -qxF "$dep" "$WORK/base.txt" && return 0
    grep -qxF "$lookup" "$WORK/lists.txt" && return 0
    grep -qxF "$lookup" "$WORK/arch.txt"
}

missing=()
pinned=()
checked=0

shopt -s nullglob
for pkg in "$pkgdir"/*.pkg.tar.zst; do
    name=$(bsdtar -xOf "$pkg" .PKGINFO 2> /dev/null | awk -F' = ' '/^pkgname/ { print $2; exit }')
    [[ -n $name ]] || { echo "verify-shedos-deps: $pkg carries no .PKGINFO" >&2; exit 2; }
    grep -qxF "$name" "$WORK/release.txt" || continue
    checked=$((checked + 1))
    while read -r dep; do
        [[ -n $dep ]] || continue
        bare=${dep%%[<>=]*}
        # An exact pin on a package the release does not publish wedges every
        # update the moment Arch moves past it.
        if [[ $dep == "$bare="* ]] && ! grep -qxF "$bare" "$WORK/release.txt"; then
            pinned+=("$name  →  $dep")
        fi
        covered "$bare" || missing+=("$name  →  $dep")
    done < <(bsdtar -xOf "$pkg" .PKGINFO 2> /dev/null | awk -F' = ' '/^depend/ { print $2 }')
done
shopt -u nullglob

(( checked > 0 )) || { echo "verify-shedos-deps: $pkgdir holds none of the release" >&2; exit 2; }

status=0
if (( ${#pinned[@]} )); then
    {
        echo 'exact-version depends on packages the release does not publish:'
        echo
        printf '  %s\n' "${pinned[@]}"
        echo
        echo 'Use an unversioned or >= dep and ship a rebuilt package in lockstep;'
        echo 'an = pin on an Arch package blocks every update once Arch moves past it.'
    } >&2
    status=1
fi

if (( ${#missing[@]} )); then
    {
        printf '%d depend(s) nothing can satisfy:\n\n' "${#missing[@]}"
        printf '  %s\n' "${missing[@]}"
        echo
        echo 'Add each to packages/official/*.txt or packages/aur.txt, then'
        echo 'regenerate archiso/packages.x86_64.'
    } >&2
    status=1
fi

(( status == 0 )) && echo "OK: every depend of the $checked release package(s) is satisfiable"
exit $status
