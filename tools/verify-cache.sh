#!/bin/bash
# Verify all packages needed for ISO build are in cache

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PACKAGES_FILE="$PROJECT_ROOT/archiso/packages.x86_64"
OFFICIAL_CACHE="/var/cache/pacman/pkg"
AUR_REPO="$PROJECT_ROOT/archiso/shedos-repo"

# Read AUR packages from packages/aur.txt (single source of truth)
AUR_FILE="$PROJECT_ROOT/packages/aur.txt"
if [ -f "$AUR_FILE" ]; then
    mapfile -t AUR_PACKAGES < <(grep -v '^#' "$AUR_FILE" | grep -v '^$' | tr -d ' ')
else
    AUR_PACKAGES=()
fi

echo "========================================"
echo "Verifying package cache completeness..."
echo "========================================"
echo ""

# Get list of official packages
MISSING=0
CHECKED=0

while IFS= read -r line; do
    # Skip comments and empty lines
    [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue

    pkg=$(echo "$line" | awk '{print $1}')

    # Skip AUR packages
    is_aur=false
    for aur_pkg in "${AUR_PACKAGES[@]}"; do
        if [ "$pkg" = "$aur_pkg" ]; then
            is_aur=true
            break
        fi
    done
    [ "$is_aur" = true ] && continue

    # ShedOS-native packages live in archiso/shedos-repo/, not /var/cache/pacman.
    # They're produced by scripts/build-shedos-packages.sh — check there instead.
    if [[ "$pkg" == shedos-* ]]; then
        CHECKED=$((CHECKED + 1))
        if ! ls "$AUR_REPO/${pkg}"-*.pkg.tar.zst >/dev/null 2>&1; then
            echo "❌ MISSING (shedos-repo): $pkg"
            MISSING=$((MISSING + 1))
        fi
        continue
    fi

    CHECKED=$((CHECKED + 1))

    # Check if package exists in cache (any version)
    if ! ls "$OFFICIAL_CACHE/${pkg}"-*.pkg.tar.zst >/dev/null 2>&1; then
        echo "❌ MISSING: $pkg"
        MISSING=$((MISSING + 1))
    fi
done < "$PACKAGES_FILE"

echo ""
echo "========================================"
echo "Packages checked: $CHECKED"
echo "Missing from cache: $MISSING"
echo "========================================"

if [ $MISSING -gt 0 ]; then
    echo ""
    echo "❌ ERROR: Some packages are missing from cache!"
    echo "Run 'sudo make download-packages' to download them."
    exit 1
else
    echo ""
    echo "✅ SUCCESS: All packages are in cache"
    echo ""
    echo "Cache statistics:"
    echo "  Official: $(ls -1 $OFFICIAL_CACHE/*.pkg.tar.zst 2>/dev/null | wc -l) packages"
    echo "  AUR:      $(ls -1 $AUR_REPO/*.pkg.tar.zst 2>/dev/null | wc -l) packages"
    echo "  Database: $(ls -1 $PROJECT_ROOT/db-cache/*.db 2>/dev/null | wc -l) files"
    exit 0
fi
