#!/usr/bin/env bash
# check-airootfs-overlaps.sh <package-dir> [<airootfs-dir>]
#
# Which files the airootfs overlay puts where a package the same pacstrap
# installs also puts one. mkarchiso lays the overlay down first and pacstrap
# runs into it, so every one of these is a file two things claim.
#
# The release's own packages are the failing half. Nothing on the overlay may
# collide with one: those packages are written in fourteen other repositories
# now, and a maintainer there adding a file at a path the profile also ships
# would break the ISO with nothing in their own repository saying so. That is
# the collision this exists to catch, and today there are none.
#
# The Arch-owned half is reported rather than failed. Ten of them exist and
# have for as long as the profile has, pacstrap has never refused one, and why
# it does not is not a thing this repository knows — pacman's rule is that a
# file on disk that no package owns is a conflict. What is written down here is
# the list and the fact that the reason is unexplained; inventing one would be
# worse than saying so.
#
# The Arch half needs a file database. SHEDOS_ARCH_OWNERS names a file of
# "<path>\t<package>" lines in place of syncing one, which is how this runs
# without root or a network; without either the Arch half says it could not be
# read and the shedos half still answers.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(dirname "$HERE")
# shellcheck source=tools/lib-manifest.sh
source "$HERE/lib-manifest.sh"

(( $# >= 1 )) || { echo 'usage: check-airootfs-overlaps.sh <package-dir> [<airootfs-dir>]' >&2; exit 2; }
pkgdir=$1
airootfs=${2:-$ROOT/archiso/airootfs}
manifest=${SHEDOS_MANIFEST:-$ROOT/release-manifest.toml}
[[ -d $pkgdir ]] || { echo "overlaps: $pkgdir does not exist" >&2; exit 2; }
[[ -d $airootfs ]] || { echo "overlaps: $airootfs does not exist" >&2; exit 2; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Every path the overlay lays down, as pacman spells them: no leading slash,
# directories left out because a directory is not a file conflict.
( cd "$airootfs" && find . -type f -o -type l ) \
    | sed 's|^\./||' | LC_ALL=C sort -u > "$WORK/overlay.txt"

manifest_read "$manifest" | awk -F'\t' '$1 == "package" { print $2 }' \
    | LC_ALL=C sort -u > "$WORK/release.txt"

# What the release's packages ship, from the packages themselves.
: > "$WORK/release-files.tsv"
shopt -s nullglob
for pkg in "$pkgdir"/*.pkg.tar.zst; do
    name=$(bsdtar -xOf "$pkg" .PKGINFO 2> /dev/null | awk -F' = ' '/^pkgname/ { print $2; exit }')
    [[ -n $name ]] || continue
    grep -qxF "$name" "$WORK/release.txt" || continue
    bsdtar -tf "$pkg" 2> /dev/null \
        | grep -v '/$' | grep -v '^\.' \
        | awk -v n="$name" '{ print $0 "\t" n }' >> "$WORK/release-files.tsv"
done
shopt -u nullglob

LC_ALL=C sort -u -o "$WORK/release-files.tsv" "$WORK/release-files.tsv"
cut -f1 "$WORK/release-files.tsv" | LC_ALL=C sort -u > "$WORK/release-paths.txt"

LC_ALL=C comm -12 "$WORK/overlay.txt" "$WORK/release-paths.txt" > "$WORK/clash.txt"

status=0
if [[ -s $WORK/clash.txt ]]; then
    printf 'the overlay collides with %d file(s) the release ships:\n\n' \
        "$(wc -l < "$WORK/clash.txt")" >&2
    while read -r path; do
        printf '  /%s\t%s\n' "$path" \
            "$(awk -F'\t' -v p="$path" '$1 == p { print $2 }' "$WORK/release-files.tsv" | paste -sd,)" >&2
    done < "$WORK/clash.txt"
    printf '\nEither the profile stops shipping the file or the package does.\n' >&2
    status=1
else
    printf 'no overlay file collides with the release (%d overlay files, %d release files)\n' \
        "$(wc -l < "$WORK/overlay.txt")" "$(wc -l < "$WORK/release-paths.txt")"
fi

# --- the Arch half, reported ------------------------------------------------

owners=''
if [[ -n ${SHEDOS_ARCH_OWNERS:-} ]]; then
    owners=$SHEDOS_ARCH_OWNERS
elif [[ $EUID -eq 0 ]]; then
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
    if pacman -Fy --noconfirm --dbpath "$WORK/db" --config "$WORK/pacman.conf" > /dev/null 2>&1; then
        owners=$WORK/owners.tsv
        : > "$owners"
        while read -r path; do
            pacman -F --dbpath "$WORK/db" --config "$WORK/pacman.conf" -q "/$path" 2> /dev/null \
                | awk -v p="$path" 'NF { print p "\t" $0 }' >> "$owners"
        done < "$WORK/overlay.txt"
    fi
fi

if [[ -z $owners || ! -f $owners ]]; then
    echo 'the Arch half was not read: no file database and no SHEDOS_ARCH_OWNERS'
else
    printf '\n%d overlay file(s) are also shipped by an Arch package:\n' \
        "$(LC_ALL=C comm -12 "$WORK/overlay.txt" \
            <(cut -f1 "$owners" | LC_ALL=C sort -u) | wc -l)"
    while read -r path owner; do
        grep -qxF "$path" "$WORK/overlay.txt" || continue
        printf '  /%s\t%s\n' "$path" "$owner"
    done < <(LC_ALL=C sort -u "$owners")
    echo
    echo 'Reported, not failed: pacstrap has never refused one of these and the'
    echo 'reason it does not is not written down anywhere this repository can read.'
fi

exit $status
