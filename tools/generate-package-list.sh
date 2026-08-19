#!/usr/bin/env bash
# generate-package-list.sh [<release-manifest.toml>]
#
# archiso/packages.x86_64: the airootfs package list.
#
# airootfs IS the installed system — Calamares' unpackfs copies it onto the
# target — so this list has to name the whole of it: every category under
# packages/official, the ISO-only officials, every AUR entry, and every package
# the release manifest names.
#
# The form is a flat resolved closure. Every transitive dependency is written
# out and every chosen provider sits at the root of pacman's resolution graph,
# so pacstrap has no virtual-provider roll to make at build time and cannot
# pick jack2 where the release means pipewire-jack.
#
# What the ShedOS half comes from is the change: the monolith learned it from a
# four-name array plus a shedos-* prefix rule, which meant a package that was
# renamed, or never carried the prefix, fell silently out of the ISO. It comes
# from the manifest now, which is the definition of the release, so a package
# the release names is on the ISO by construction.
#
# Needs root: the closure is resolved against a pacman database this syncs into
# a tempdir rather than against the host's.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(dirname "$HERE")
# shellcheck source=tools/lib-manifest.sh
source "$HERE/lib-manifest.sh"

PACKAGES_DIR=$ROOT/packages
OUTPUT_FILE=$ROOT/archiso/packages.x86_64
MANIFEST=${1:-$ROOT/release-manifest.toml}

[[ $EUID -eq 0 ]] || { echo 'generate-package-list: must be run as root' >&2; exit 1; }
[[ -f $MANIFEST ]] || { echo "generate-package-list: $MANIFEST does not exist" >&2; exit 2; }

TMPDIR_=$(mktemp -d)
trap 'rm -rf "$TMPDIR_"' EXIT
mkdir -p "$TMPDIR_/db"

# The manifest is read for its names only; nothing here touches the channel.
manifest_read "$MANIFEST" > "$TMPDIR_/manifest.tsv"
awk -F'\t' '$1 == "package" { print $2 }' "$TMPDIR_/manifest.tsv" \
    | LC_ALL=C sort -u > "$TMPDIR_/shedos.txt"
(( $(wc -l < "$TMPDIR_/shedos.txt") > 0 )) \
    || { echo 'generate-package-list: the manifest names no packages' >&2; exit 2; }

is_release() { grep -qxF "$1" "$TMPDIR_/shedos.txt"; }

# The roots, in the order the lists are read. A manifest name stays a root
# where Arch also has one — cage is in desktop.txt and Arch builds a cage, and
# dropping it as a root would drop its dependencies out of the closure with it.
# What the release replaces is the package, not what the package needs.
ROOTS=()
for f in "$PACKAGES_DIR"/official/*.txt "$PACKAGES_DIR"/iso-only-official.txt \
         "$PACKAGES_DIR"/aur.txt; do
    [[ -f $f ]] || continue
    while IFS= read -r pkg; do
        [[ -z $pkg || $pkg =~ ^[[:space:]]*# ]] && continue
        pkg=${pkg%%[[:space:]]*}
        ROOTS+=("$pkg")
    done < "$f"
done

echo "Roots: ${#ROOTS[@]} packages (before transitive resolution)"

# The same shape as the build-time pacman.conf, minus the local repository:
# what is resolved here is the Arch half, and the release's own packages are
# written out from the manifest below.
cat > "$TMPDIR_/pacman.conf" << 'EOF'
[options]
HoldPkg     = pacman glibc
Architecture = x86_64
SigLevel    = Never
LocalFileSigLevel = Optional

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF

pacman -Sy --noconfirm --dbpath "$TMPDIR_/db" --config "$TMPDIR_/pacman.conf" > /dev/null

known() {
    pacman -Si --dbpath "$TMPDIR_/db" --config "$TMPDIR_/pacman.conf" "$1" > /dev/null 2>&1
}

ARCH_ROOTS=()
AUR_LITERAL=()
for r in "${ROOTS[@]}"; do
    if known "$r"; then
        ARCH_ROOTS+=("$r")
    elif ! is_release "$r"; then
        AUR_LITERAL+=("$r")
    fi
done

# The release's names come out of the resolved set and go back in from the
# manifest, at the manifest's spelling. A name the channel replaces would
# otherwise be listed twice — once as Arch's and once as the release's — and
# pacstrap would be free to take either.
pacman -Sp --noconfirm \
    --dbpath "$TMPDIR_/db" \
    --config "$TMPDIR_/pacman.conf" \
    --print-format '%n' \
    "${ARCH_ROOTS[@]}" \
    | LC_ALL=C sort -u \
    | LC_ALL=C comm -23 - "$TMPDIR_/shedos.txt" > "$TMPDIR_/resolved.txt"

{
    cat << 'EOF'
# ShedOS airootfs package list
#
# AUTO-GENERATED; DO NOT EDIT MANUALLY.
# Source: packages/official/*.txt + packages/aur.txt + release-manifest.toml
# Regenerate: sudo tools/generate-package-list.sh
#
# Flat resolved closure. Every transitive dep is listed explicitly so
# pacstrap has no virtual-provider rolls to do at build time.

EOF
    cat "$TMPDIR_/resolved.txt"
    echo ""
    echo "# --- AUR (built by tools/build-aur-packages.sh) ---"
    printf '%s\n' "${AUR_LITERAL[@]}" | LC_ALL=C sort -u
    echo ""
    echo "# --- the release (fetched by tools/fetch-packages.sh) ---"
    cat "$TMPDIR_/shedos.txt"
} > "$OUTPUT_FILE"

if [[ -n ${SUDO_USER:-} ]]; then
    chown "$SUDO_USER:$(id -gn "$SUDO_USER")" "$OUTPUT_FILE"
fi

TOTAL=$(grep -cv '^#\|^$' "$OUTPUT_FILE")
RESOLVED=$(wc -l < "$TMPDIR_/resolved.txt")
RELEASE=$(wc -l < "$TMPDIR_/shedos.txt")
echo "Wrote $OUTPUT_FILE ($TOTAL packages: $RESOLVED Arch + ${#AUR_LITERAL[@]} AUR + $RELEASE from the release)"
