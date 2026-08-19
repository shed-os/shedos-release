#!/bin/bash
# Download every Arch package the ISO build will install, and freeze the
# databases the versions were chosen from, so mkarchiso runs with no network at
# all and a rebuild installs the same bytes as the run that froze them.
#
# The AUR packages are built here (step 1) and the release's own packages are
# fetched before this runs; both already sit in the ISO's local repository, and
# this covers the third set: the Arch packages those two need and the ones the
# source lists name directly.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
# shellcheck source=tools/lib-manifest.sh
source "$SCRIPT_DIR/lib-manifest.sh"
# Source of truth for the package-prefetch list is packages/official/*.txt.
# archiso/packages.x86_64 only names the ISO-boot packages + shedos-meta now
# (shedos-meta's depends= pulls in the rest at pacstrap time). Driving the
# prefetch off packages.x86_64 would miss hundreds of transitive-via-meta
# packages; so we read the per-group txts directly and let pacman -Syw
# resolve transitive deps from there.
CACHE_DIR="/var/cache/pacman/pkg"
RELEASE_MANIFEST="${SHEDOS_MANIFEST:-$PROJECT_ROOT/release-manifest.toml}"

echo "=================================="
echo "Pre-downloading packages for ShedOS"
echo "=================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# Step 1: Build AUR packages first (reuse existing script)
echo ""
echo "Step 1/3: Building AUR packages..."
echo "=================================="
"$SCRIPT_DIR/build-aur-packages.sh"
echo "AUR packages built successfully"
echo ""

# Step 2: Download official repository packages
echo "Step 2/3: Downloading official repository packages..."
echo "=================================="

# Read AUR packages from packages/aur.txt (single source of truth)
AUR_FILE="$PROJECT_ROOT/packages/aur.txt"
if [ ! -f "$AUR_FILE" ]; then
    echo "ERROR: AUR package list not found: $AUR_FILE"
    exit 1
fi

# Read packages, filtering out comments and empty lines
mapfile -t AUR_PACKAGES < <(grep -v '^#' "$AUR_FILE" | grep -v '^$' | tr -d ' ')
echo "Found ${#AUR_PACKAGES[@]} AUR packages to exclude from download"

# Create temporary directory for package list
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# official/*.txt + iso-only-official.txt, the same sources generate-package-list.sh
# folds into packages.x86_64; strip comments/blank, dedupe.
{
    find "$PROJECT_ROOT/packages/official" -maxdepth 1 -type f -name '*.txt' -print0 \
        | xargs -0 grep -hEv '^\s*(#|$)'
    grep -hEv '^\s*(#|$)' "$PROJECT_ROOT/packages/iso-only-official.txt"
} \
    | awk '{print $1}' \
    | sort -u > "$TEMP_DIR/all_packages.txt"

# Filter out AUR packages - they cannot be downloaded via pacman -Sw
# This prevents "error: target not found" messages
cp "$TEMP_DIR/all_packages.txt" "$TEMP_DIR/pkglist.txt"
for pkg in "${AUR_PACKAGES[@]}"; do
    sed -i "/^${pkg}$/d" "$TEMP_DIR/pkglist.txt"
done

# The release's own packages come off the channel, not off a mirror, so a
# request for one is a "target not found" rather than a download. Every name
# the manifest carries is dropped from the list for that reason.
manifest_read "$RELEASE_MANIFEST" \
    | awk -F'\t' '$1 == "package" { print $2 }' \
    | LC_ALL=C sort -u > "$TEMP_DIR/release.txt"
if [ ! -s "$TEMP_DIR/release.txt" ]; then
    echo "ERROR: could not read any package name out of $RELEASE_MANIFEST" >&2
    exit 1
fi
LC_ALL=C sort -u -o "$TEMP_DIR/pkglist.txt" "$TEMP_DIR/pkglist.txt"
LC_ALL=C comm -23 "$TEMP_DIR/pkglist.txt" "$TEMP_DIR/release.txt" \
    > "$TEMP_DIR/pkglist.arch" && mv "$TEMP_DIR/pkglist.arch" "$TEMP_DIR/pkglist.txt"

# What the release's packages need from Arch. The metapackage closure covers
# what an installed system pulls, and this covers the rest — the installer's
# dependencies are deliberately outside that closure and still have to be on
# the ISO. Read from the fetched packages themselves, which is the only copy
# of their depends this repository has.
RELEASE_DEPS=()
shopt -s nullglob
for pkg in "$AUR_REPO_DIR"/*.pkg.tar.zst; do
    name=$(bsdtar -xOf "$pkg" .PKGINFO 2>/dev/null \
        | awk -F' = ' '/^pkgname/ { print $2; exit }')
    grep -qxF "$name" "$TEMP_DIR/release.txt" || continue
    while read -r dep; do
        bare="${dep%%[<>=]*}"
        [[ -n "$bare" ]] || continue
        grep -qxF "$bare" "$TEMP_DIR/release.txt" && continue
        RELEASE_DEPS+=("$bare")
    done < <(bsdtar -xOf "$pkg" .PKGINFO 2>/dev/null | awk -F' = ' '/^depend/ { print $2 }')
done
shopt -u nullglob
if (( ${#RELEASE_DEPS[@]} > 0 )); then
    printf '%s\n' "${RELEASE_DEPS[@]}" >> "$TEMP_DIR/pkglist.txt"
    LC_ALL=C sort -u -o "$TEMP_DIR/pkglist.txt" "$TEMP_DIR/pkglist.txt"
    echo "Release-package deps added for prefetch: ${#RELEASE_DEPS[@]} name(s)"
fi

TOTAL_PACKAGES=$(wc -l < "$TEMP_DIR/all_packages.txt")
OFFICIAL_PACKAGES=$(wc -l < "$TEMP_DIR/pkglist.txt")
AUR_COUNT=${#AUR_PACKAGES[@]}

echo "Total packages: $TOTAL_PACKAGES"
echo "Official packages to download: $OFFICIAL_PACKAGES"
echo "AUR packages (excluded from download): $AUR_COUNT"
echo ""

# Download packages using pacman -Sw (download only, don't install)
# pacman automatically skips packages that are already cached at the correct version
echo "Downloading packages to $CACHE_DIR..."
echo "Pacman will automatically skip already-cached packages."
echo ""

# Use pacman -Sw which:
# 1. Only downloads packages not already in cache (or wrong version)
# 2. Handles dependencies automatically
# 3. Uses the synced database for correct URLs
echo "Starting package download..."

# Create a download-specific pacman.conf based on archiso/pacman.conf.
# It registers [core]/[extra]/[multilib] for official Arch mirrors plus the
# ISO-local repository so pacman's dependency resolver can satisfy
# AUR-only entries surfaced by step 2 below (`libcrypto.so=1.1` →
# `openssl-1.1`, `libfprint-tod`, …). Without [shedos-repo] in scope the
# resolver errors `target not found` on any AUR pkg whose runtime depends
# resolve to other AUR pkgs we ship.
AUR_REPO_DIR="${SHEDOS_ISO_REPO:-$PROJECT_ROOT/out/shedos-repo}"
DOWNLOAD_PACMAN_CONF="$TEMP_DIR/pacman-download.conf"
cat > "$DOWNLOAD_PACMAN_CONF" << 'EOF'
[options]
HoldPkg     = pacman glibc
Architecture = x86_64
Color
CheckSpace
ParallelDownloads = 5
DownloadUser = root
DisableSandbox
SigLevel    = Never
LocalFileSigLevel = Optional

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF

# Append [shedos-repo] only when its DB is actually present; the AUR build
# step normally produces one but a fresh checkout with a cold AUR cache
# could race ahead of repo-add. Guarding the append keeps pacman from
# erroring on a missing repo file.
if [ -f "$AUR_REPO_DIR/shedos-repo.db" ]; then
    cat >> "$DOWNLOAD_PACMAN_CONF" <<EOF

[shedos-repo]
SigLevel = Never
Server = file://$AUR_REPO_DIR
EOF
fi

echo "Using download pacman.conf (core/extra/multilib + local shedos-repo)..."

# Create temporary database path to avoid host package conflicts
TEMP_DBPATH="$TEMP_DIR/db"
mkdir -p "$TEMP_DBPATH"

# Download all packages AND their dependencies
# This ensures the exact same packages are downloaded as will be installed
# 1. Download official packages
echo "Downloading official packages..."
# Use --dbpath to isolate from host system
pacman -Syw --noconfirm --dbpath "$TEMP_DBPATH" --config "$DOWNLOAD_PACMAN_CONF" $(cat "$TEMP_DIR/pkglist.txt" | tr '\n' ' ')

# 2. Automatically resolve and download dependencies for built AUR packages
echo "Resolving dependencies for built AUR packages..."
if [ -d "$AUR_REPO_DIR" ]; then
    # Create a list of all dependencies required by our built AUR packages
    # We use pacman -Qpi to query the built package files directly for detailed info
    echo "Extracting dependencies from local packages..."
    # Drop the release's own names: those come off the channel, and asking a
    # mirror for one fails the whole download with `target not found`.
    find "$AUR_REPO_DIR" -name "*.pkg.tar.zst" -exec pacman -Qpi {} + | \
        grep "^Depends On" | \
        cut -d':' -f2 | \
        tr ' ' '\n' | \
        sed 's/^[ \t]*//' | \
        grep -v "None" | \
        LC_ALL=C sort -u | \
        grep -v "^$" | \
        LC_ALL=C comm -23 - "$TEMP_DIR/release.txt" > "$TEMP_DIR/aur_deps.txt" || true
    
    DEPS_COUNT=$(wc -l < "$TEMP_DIR/aur_deps.txt")
    echo "Found $DEPS_COUNT unique dependencies for AUR packages."
    
    if [ "$DEPS_COUNT" -gt 0 ]; then
        # Download these dependencies
        # pacman -Sw will automatically skip what's already downloaded or installed and up-to-date
        echo "Downloading AUR dependencies..."
        # Use --dbpath to isolate from host system
        pacman -Syw --noconfirm --dbpath "$TEMP_DBPATH" --config "$DOWNLOAD_PACMAN_CONF" $(cat "$TEMP_DIR/aur_deps.txt" | tr '\n' ' ')
    else
        echo "No additional dependencies found for AUR packages."
    fi
else
    echo "WARNING: AUR repo dir not found, skipping dependency resolution."
fi

echo ""
echo "=================================="


echo "All packages downloaded/built successfully."
echo "=================================="

# Step 3: Freeze package database state for deterministic builds
echo ""
echo "Step 3/3: Freezing package database state..."
echo "=================================="

DB_CACHE_DIR="$PROJECT_ROOT/db-cache"
mkdir -p "$DB_CACHE_DIR"

# Copy current sync databases to cache from TEMP_DBPATH
# These represent the exact package versions we just downloaded
# Note: dbpath structure is usually dbpath/sync/*.db
cp "$TEMP_DBPATH/sync/"*.db "$DB_CACHE_DIR/" 2>/dev/null || true

echo "Databases cached in: $DB_CACHE_DIR"
echo ""
echo "=================================="
echo "Package download complete!"
echo "=================================="
echo "Official packages cached in: $CACHE_DIR"
echo "AUR + release packages in: $AUR_REPO_DIR"
echo "Package databases frozen in: $DB_CACHE_DIR"
echo ""
echo "tools/build-iso.sh now installs EXACTLY these package versions"
