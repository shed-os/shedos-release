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

# List of AUR packages to exclude (must match build-aur-packages.sh)
AUR_PACKAGES=(
    "walker"
    "calamares"
    "yay"
    "visual-studio-code-bin"
    "google-chrome"
    "slack-desktop"
    "obsidian-bin"
    "hadolint-bin"
)

# Create temporary directory for package list
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Extract package names (remove comments, blank lines, and versions)
grep -v '^#' "$PACKAGES_FILE" | grep -v '^$' | awk '{print $1}' > "$TEMP_DIR/all_packages.txt"

# Filter out AUR packages
cp "$TEMP_DIR/all_packages.txt" "$TEMP_DIR/pkglist.txt"
for pkg in "${AUR_PACKAGES[@]}"; do
    sed -i "/^${pkg}$/d" "$TEMP_DIR/pkglist.txt"
done

TOTAL_PACKAGES=$(wc -l < "$TEMP_DIR/all_packages.txt")
OFFICIAL_PACKAGES=$(wc -l < "$TEMP_DIR/pkglist.txt")
AUR_COUNT=$((TOTAL_PACKAGES - OFFICIAL_PACKAGES))

echo "Total packages: $TOTAL_PACKAGES"
echo "Official packages to download: $OFFICIAL_PACKAGES"
echo "AUR packages (already built): $AUR_COUNT"
echo ""

# Download packages using pacman
echo "Downloading packages to $CACHE_DIR..."
echo "This may take a while depending on your connection..."
echo ""

# Use pacman to download packages
# -Syw = sync databases and download only (don't install)
# --asdeps = mark packages as dependencies (doesn't affect download)
# --cachedir = where to store downloaded packages
# --needed = skip packages that are already in cache
# Note: We use the system's default pacman.conf (not ISO's) since we're only
# downloading official repo packages. AUR packages are already in shedos-repo.
# We DON'T use -d flag so dependencies are downloaded too!

echo "Starting package download (this may take several minutes)..."

# Create fake root so pacman thinks no packages are installed
FAKE_ROOT=$(mktemp -d)
mkdir -p "$FAKE_ROOT/var/lib/pacman/local"  # Empty - nothing installed
mkdir -p "$FAKE_ROOT/var/lib/pacman/sync"    # Need for repo databases

# Copy sync databases so pacman knows what packages are available
echo "Setting up fake root environment..."
cp /var/lib/pacman/sync/*.db "$FAKE_ROOT/var/lib/pacman/sync/"

# Get list of ALL package URLs using fake root
# Use empty cache dir too, so pacman outputs http:// URLs instead of file:// URLs
echo "Resolving all package URLs (including dependencies)..."
FAKE_CACHE=$(mktemp -d)
pacman -Sp \
    --root "$FAKE_ROOT" \
    --cachedir "$FAKE_CACHE" \
    --print-format '%n %l' \
    $(cat "$TEMP_DIR/pkglist.txt") > "$TEMP_DIR/package_urls.txt" 2>&1
rm -rf "$FAKE_CACHE"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to resolve package URLs!"
    cat "$TEMP_DIR/package_urls.txt"
    rm -rf "$FAKE_ROOT"
    exit 1
fi

# Clean up fake root (don't need it anymore)
rm -rf "$FAKE_ROOT"

# Download each package
TOTAL=$(grep -c '\.pkg\.tar\.zst' "$TEMP_DIR/package_urls.txt" || echo 0)
DOWNLOADED=0
SKIPPED=0

echo "Found $TOTAL packages to download (including all dependencies)..."
echo ""

while read -r name url; do
    # Skip empty lines
    [ -z "$name" ] && continue
    [ -z "$url" ] && continue

    # Skip non-package URLs
    [[ ! "$url" =~ \.pkg\.tar\.zst$ ]] && continue

    filename=$(basename "$url")

    # Check if already in cache
    if [ -f "$CACHE_DIR/$filename" ]; then
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Download the package
    echo "Downloading: $name ($filename)..."
    if curl -f -L -o "$CACHE_DIR/$filename" "$url" 2>&1 | grep -v "^  % Total"; then
        DOWNLOADED=$((DOWNLOADED + 1))
    else
        echo "ERROR: Failed to download $name from $url"
        exit 1
    fi
done < "$TEMP_DIR/package_urls.txt"

# Double-check that critical packages were downloaded
echo ""
echo "Verifying critical packages..."
MISSING_CRITICAL=0
for pkg in lsof glu; do
    if ! ls "$CACHE_DIR/${pkg}"-*.pkg.tar.zst >/dev/null 2>&1; then
        echo "ERROR: Critical package missing: $pkg"
        MISSING_CRITICAL=$((MISSING_CRITICAL + 1))
    fi
done

if [ $MISSING_CRITICAL -gt 0 ]; then
    echo "ERROR: $MISSING_CRITICAL critical packages are missing!"
    echo "Dumping first 20 lines of package_urls.txt for debugging:"
    head -20 "$TEMP_DIR/package_urls.txt"
    exit 1
fi

echo ""
echo "Downloaded: $DOWNLOADED packages"
echo "Already cached: $SKIPPED packages"

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
