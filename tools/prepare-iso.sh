#!/usr/bin/env bash
# prepare-iso.sh [<release-manifest.toml>]
#
# Everything the ISO build does before mkarchiso: fetch the release, build the
# AUR packages, prefetch and freeze the Arch half, regenerate the package list,
# and lay out a profile directory mkarchiso can be pointed at.
#
# The decisive difference from the build this replaces is where the ShedOS
# packages come from. They used to be built here, out of a working tree, which
# meant the ISO shipped a rebuild of the same source rather than the release —
# same version, different bytes, verified by nothing. They are fetched now,
# from the channel, at the shas the manifest names, and the ISO bakes the same
# signed files the fleet upgrades to.
#
# Needs root: pacstrap's caches, the isolated database syncs, and makepkg's
# build user all want it.
#
# Environment:
#   SHEDOS_ISO_TAG          version stamped into profiledef (default: the
#                           manifest's release)
#   SHEDOS_CHANNEL          test or stable; the marker installs read to pick a
#                           channel (default test)
#   SHEDOS_ISO_REPO         the ISO's local repository (default out/shedos-repo)
#   SHEDOS_BUILD_DIR        the profile mkarchiso is given (default build)
#   SHEDOS_LOCAL_PACKAGES   a directory of locally-built packages that stand in
#                           for the release's for this build — the local-overlay
#                           flow, and never what CI does
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(dirname "$HERE")
# shellcheck source=tools/lib-fetch.sh
source "$HERE/lib-fetch.sh"

# Claude Code is baked into /etc/skel from the official installer at build
# time — inert bytes in the squashfs, never a signed repo package. Pinned for
# reproducible ISOs; the sha256 for each version is recorded beside it in
# bake-claude-code.sh, and both move together.
CLAUDE_CODE_VERSION=2.1.170

MANIFEST=${1:-$ROOT/release-manifest.toml}
export SHEDOS_MANIFEST=$MANIFEST
ISO_REPO=${SHEDOS_ISO_REPO:-$ROOT/out/shedos-repo}
export SHEDOS_ISO_REPO=$ISO_REPO
BUILD_DIR=${SHEDOS_BUILD_DIR:-$ROOT/build}
PROFILE_DIR=$ROOT/archiso
DB_CACHE=$ROOT/db-cache
LOCAL_PACKAGES=${SHEDOS_LOCAL_PACKAGES:-}

[[ $EUID -eq 0 ]] || { echo 'prepare-iso: must be run as root' >&2; exit 1; }
[[ -f $MANIFEST ]] || { echo "prepare-iso: $MANIFEST does not exist" >&2; exit 2; }

RELEASE=$(awk -F'"' '/^version = /{ print $2; exit }' "$MANIFEST")
ISO_VER=${SHEDOS_ISO_TAG:-$RELEASE}
CHANNEL=${SHEDOS_CHANNEL:-test}
[[ $CHANNEL == test || $CHANNEL == stable ]] \
    || { echo "prepare-iso: channel must be test or stable, not $CHANNEL" >&2; exit 2; }

say() { printf '\n== %s\n' "$1"; }

# --- the release ------------------------------------------------------------

say "fetching the release ($RELEASE) into $ISO_REPO"
mkdir -p "$ISO_REPO"
bash "$HERE/fetch-packages.sh" "$MANIFEST" "$ISO_REPO"

# A locally-built package stands in for the one the manifest names, and the
# fetched copy goes rather than sitting beside it: two versions of one name in
# a repository is a roll, and this flow exists so that a person can be certain
# which one the ISO took.
if [[ -n $LOCAL_PACKAGES ]]; then
    say "substituting locally-built packages from $LOCAL_PACKAGES"
    [[ -d $LOCAL_PACKAGES ]] || { echo "prepare-iso: $LOCAL_PACKAGES does not exist" >&2; exit 2; }
    shopt -s nullglob
    local_pkgs=("$LOCAL_PACKAGES"/*.pkg.tar.zst)
    shopt -u nullglob
    (( ${#local_pkgs[@]} )) || { echo "prepare-iso: $LOCAL_PACKAGES holds no packages" >&2; exit 2; }
    for pkg in "${local_pkgs[@]}"; do
        name=$(bsdtar -xOf "$pkg" .PKGINFO | awk -F' = ' '/^pkgname/ { print $2; exit }')
        [[ -n $name ]] || { echo "prepare-iso: $pkg carries no .PKGINFO" >&2; exit 2; }
        for stale in "$ISO_REPO/$name"-*.pkg.tar.zst; do
            [[ -e $stale ]] || continue
            base=$(basename "$stale")
            [[ ${base%-*-*-*.pkg.tar.zst} == "$name" ]] || continue
            rm -f "$stale" "$stale.sig"
        done
        cp -v "$pkg" "$ISO_REPO/"
        echo "  local: $name supersedes the release's"
    done
fi

# --- the package list -------------------------------------------------------

say 'regenerating archiso/packages.x86_64'
bash "$HERE/generate-package-list.sh" "$MANIFEST"

# --- the AUR half and the Arch half ----------------------------------------

say 'building the AUR packages and freezing the Arch databases'
bash "$HERE/download-packages.sh"

say 'registering everything in the ISO repository'
(
    cd "$ISO_REPO"
    shopt -s nullglob
    pkgs=(*.pkg.tar.zst)
    (( ${#pkgs[@]} )) || { echo 'prepare-iso: the ISO repository is empty' >&2; exit 1; }
    repo-add -q -p shedos-repo.db.tar.gz "${pkgs[@]}" > /dev/null
)
[[ -e $ISO_REPO/shedos-repo.db ]] \
    || { echo "prepare-iso: repo-add left no database in $ISO_REPO" >&2; exit 1; }

# --- the pre-flight checks --------------------------------------------------

say 'checking the release packages can be satisfied'
bash "$HERE/verify-shedos-deps.sh" "$ISO_REPO" "$MANIFEST"

say 'checking the overlay against what pacstrap installs'
bash "$HERE/check-airootfs-overlaps.sh" "$ISO_REPO" "$PROFILE_DIR/airootfs"

say 'checking every package the list names is here'
bash "$HERE/verify-cache.sh"

# --- the profile ------------------------------------------------------------

say "laying out $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cp -r "$PROFILE_DIR"/. "$BUILD_DIR/"

[[ -f $BUILD_DIR/pacman.conf.in ]] \
    || { echo "prepare-iso: the profile has no pacman.conf.in" >&2; exit 1; }
sed "s|@SHEDOS_REPO@|$ISO_REPO|g" "$BUILD_DIR/pacman.conf.in" > "$BUILD_DIR/pacman.conf"
rm -f "$BUILD_DIR/pacman.conf.in"

# The channel marker rides the squashfs into installs, where shedos-system's
# install fence reads it to point [shedos] at /test or /stable.
[[ -f $BUILD_DIR/airootfs/etc/pacman.conf.in ]] \
    || { echo "prepare-iso: the profile has no airootfs pacman.conf.in" >&2; exit 1; }
install -d "$BUILD_DIR/airootfs/etc/shedos"
printf '%s\n' "$CHANNEL" > "$BUILD_DIR/airootfs/etc/shedos/channel"
cp "$BUILD_DIR/airootfs/etc/pacman.conf.in" "$BUILD_DIR/airootfs/etc/pacman.conf"
rm -f "$BUILD_DIR/airootfs/etc/pacman.conf.in"

sed -i "s|@SHEDOS_VERSION@|$ISO_VER|g" "$BUILD_DIR/profiledef.sh"
if grep -q '@SHEDOS_VERSION@' "$BUILD_DIR/profiledef.sh"; then
    echo 'prepare-iso: profiledef.sh still carries a placeholder' >&2
    exit 1
fi

# The installer package says DEVELOPMENT because it is built without knowing
# which release it will ship on; the hook that stamps it takes the release the
# same way profiledef does, and strips itself out of the squashfs afterwards.
version_hook=$BUILD_DIR/airootfs/etc/pacman.d/hooks/35-shedos-installer-version.hook
[[ -f $version_hook ]] || { echo "prepare-iso: the version hook is not in the profile" >&2; exit 1; }
sed -i "s|@SHEDOS_VERSION@|$RELEASE|g" "$version_hook"

say 'restoring the frozen databases'
if ! compgen -G "$DB_CACHE/*.db" > /dev/null; then
    echo "prepare-iso: no frozen databases in $DB_CACHE" >&2
    exit 1
fi
mkdir -p "$BUILD_DIR/db-cache"
cp "$DB_CACHE"/*.db "$BUILD_DIR/db-cache/"
echo "  $(find "$BUILD_DIR/db-cache" -name '*.db' | wc -l) database(s)"

say 'copying the cached Arch packages'
mkdir -p "$BUILD_DIR/pkg-cache"
# The AUR builds and the release's packages are served out of the ISO
# repository; a copy of either in pacman's cache is another build of the same
# name, and the two would race for the same filename here.
{
    grep -v '^#' "$ROOT/packages/aur.txt" | grep -v '^$' | awk '{ print $1 "-*.pkg.tar.zst" }'
    manifest_read "$MANIFEST" | awk -F'\t' '$1 == "package" { print $2 "-*.pkg.tar.zst" }'
} | LC_ALL=C sort -u > "$BUILD_DIR/repo_excludes.txt"
echo "  excluding $(wc -l < "$BUILD_DIR/repo_excludes.txt") pattern(s) the ISO repository answers for"
rsync -a --exclude-from="$BUILD_DIR/repo_excludes.txt" \
    /var/cache/pacman/pkg/*.pkg.tar.zst "$BUILD_DIR/pkg-cache/" 2> /dev/null || true

# Keep only what the list names. A package dropped from packages/ leaves its
# last build in pacman's cache, and without this it would go on riding into
# every ISO because pacstrap never asks for it and nothing ever removes it.
awk '!/^#/ && NF { print $1 }' "$ROOT/archiso/packages.x86_64" \
    | LC_ALL=C sort -u > "$BUILD_DIR/keep_pkgs.txt"
pruned=0
shopt -s nullglob
for f in "$BUILD_DIR"/pkg-cache/*.pkg.tar.zst; do
    base=$(basename "$f")
    grep -qxF "${base%-*-*-*.pkg.tar.zst}" "$BUILD_DIR/keep_pkgs.txt" && continue
    rm -f "$f"
    pruned=$((pruned + 1))
done
shopt -u nullglob
rm -f "$BUILD_DIR/keep_pkgs.txt" "$BUILD_DIR/repo_excludes.txt"
echo "  $(find "$BUILD_DIR/pkg-cache" -name '*.pkg.tar.zst' | wc -l) cached package(s), $pruned pruned"

say 'configuring pacman to build offline'
mkdir -p "$BUILD_DIR/scripts"
sed "s|@SHEDOS_REPO@|$ISO_REPO|g" "$HERE/pacman-offline-download.sh" \
    > "$BUILD_DIR/scripts/pacman-offline-download.sh"
chmod +x "$BUILD_DIR/scripts/pacman-offline-download.sh"
sed -i "/^\[options\]/a CacheDir = $BUILD_DIR/pkg-cache/" "$BUILD_DIR/pacman.conf"
sed -i "s|^XferCommand.*|XferCommand = $BUILD_DIR/scripts/pacman-offline-download.sh %o %u|" \
    "$BUILD_DIR/pacman.conf"

say 'baking Claude Code into /etc/skel'
bash "$HERE/bake-claude-code.sh" "$CLAUDE_CODE_VERSION" "$BUILD_DIR/airootfs/etc/skel"

printf '\nprepare-iso: %s ready for mkarchiso (release %s, channel %s)\n' \
    "$BUILD_DIR" "$ISO_VER" "$CHANNEL"
