#!/bin/bash
# Download all packages for ShedOS ISO build
# This pre-downloads packages to avoid network issues during mkarchiso

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
# Source of truth for the package-prefetch list is packages/official/*.txt.
# archiso/packages.x86_64 only names the ISO-boot packages + shedos-meta now
# (shedos-meta's depends= pulls in the rest at pacstrap time). Driving the
# prefetch off packages.x86_64 would miss hundreds of transitive-via-meta
# packages; so we read the per-group txts directly and let pacman -Syw
# resolve transitive deps from there.
CACHE_DIR="/var/cache/pacman/pkg"

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
echo "Step 1/2: Building AUR packages..."
echo "=================================="
"$SCRIPT_DIR/build-aur-packages.sh"
echo "AUR packages built successfully"
echo ""

# Step 2: Download official repository packages
echo "Step 2/2: Downloading official repository packages..."
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

# Concatenate every packages/official/*.txt, strip comments/blank, dedupe.
# These files are the source of truth for which Arch packages ship by default.
find "$PROJECT_ROOT/packages/official" -maxdepth 1 -type f -name '*.txt' -print0 \
    | xargs -0 grep -hEv '^\s*(#|$)' \
    | awk '{print $1}' \
    | sort -u > "$TEMP_DIR/all_packages.txt"

# Filter out AUR packages - they cannot be downloaded via pacman -Sw
# This prevents "error: target not found" messages
cp "$TEMP_DIR/all_packages.txt" "$TEMP_DIR/pkglist.txt"
for pkg in "${AUR_PACKAGES[@]}"; do
    sed -i "/^${pkg}$/d" "$TEMP_DIR/pkglist.txt"
done

# Filter out ShedOS native packages; they're built locally by
# scripts/build-shedos-packages.sh into archiso/shedos-repo/, not fetched
# from official mirrors.
sed -i '/^shedos-/d' "$TEMP_DIR/pkglist.txt"

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
# local archiso/shedos-repo so pacman's dependency resolver can satisfy
# AUR-only entries surfaced by step 2 below (`libcrypto.so=1.1` →
# `openssl-1.1`, `libfprint-tod`, …). Without [shedos-repo] in scope the
# resolver errors `target not found` on any AUR pkg whose runtime depends
# resolve to other AUR pkgs we ship.
AUR_REPO_DIR="$PROJECT_ROOT/archiso/shedos-repo"
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
    find "$AUR_REPO_DIR" -name "*.pkg.tar.zst" -exec pacman -Qpi {} + | \
        grep "^Depends On" | \
        cut -d':' -f2 | \
        tr ' ' '\n' | \
        sed 's/^[ \t]*//' | \
        grep -v "None" | \
        sort -u | \
        grep -v "^$" > "$TEMP_DIR/aur_deps.txt" || true
    
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
echo "AUR packages in: $PROJECT_ROOT/archiso/shedos-repo/"
echo "Package databases frozen in: $DB_CACHE_DIR"
echo ""
echo "Now you can run 'make iso' and it will use EXACTLY these package versions"
