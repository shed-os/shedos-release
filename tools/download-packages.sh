#!/bin/bash
# Download all packages for shedOS ISO build
# This pre-downloads packages to avoid network issues during mkarchiso

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PACKAGES_FILE="$PROJECT_ROOT/archiso/packages.x86_64"
PACMAN_CONF="$PROJECT_ROOT/archiso/pacman.conf"
CACHE_DIR="/var/cache/pacman/pkg"

echo "=================================="
echo "Pre-downloading packages for shedOS"
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

# Extract package names (remove comments, blank lines, and versions)
grep -v '^#' "$PACKAGES_FILE" | grep -v '^$' | awk '{print $1}' > "$TEMP_DIR/all_packages.txt"

# Filter out AUR packages - they cannot be downloaded via pacman -Sw
# This prevents "error: target not found" messages
cp "$TEMP_DIR/all_packages.txt" "$TEMP_DIR/pkglist.txt"
for pkg in "${AUR_PACKAGES[@]}"; do
    sed -i "/^${pkg}$/d" "$TEMP_DIR/pkglist.txt"
done

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

# Create a download-specific pacman.conf based on archiso/pacman.conf
# We exclude shedos-repo since those are local AUR packages (not downloadable)
# but keep everything else identical for consistent dependency resolution
DOWNLOAD_PACMAN_CONF="$TEMP_DIR/pacman-download.conf"
cat > "$DOWNLOAD_PACMAN_CONF" << 'EOF'
[options]
HoldPkg     = pacman glibc
Architecture = x86_64
Color
CheckSpace
ParallelDownloads = 5
SigLevel    = Never
LocalFileSigLevel = Optional

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF

echo "Using download pacman.conf (matches archiso, excludes local shedos-repo)..."

# Download all packages AND their dependencies
# This ensures the exact same packages are downloaded as will be installed
echo "Downloading packages and all dependencies..."
pacman -Syw --noconfirm --config "$DOWNLOAD_PACMAN_CONF" $(cat "$TEMP_DIR/pkglist.txt" | tr '\n' ' ')

echo ""
echo "=================================="
echo "All packages downloaded successfully"
echo "=================================="

# Step 3: Freeze package database state for deterministic builds
echo ""
echo "Step 3/3: Freezing package database state..."
echo "=================================="

DB_CACHE_DIR="$PROJECT_ROOT/db-cache"
mkdir -p "$DB_CACHE_DIR"

# Copy current sync databases to cache
# These represent the exact package versions we just downloaded
cp /var/lib/pacman/sync/*.db "$DB_CACHE_DIR/" 2>/dev/null || true

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
