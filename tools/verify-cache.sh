#!/bin/bash
# Every package archiso/packages.x86_64 names is on this machine already:
# the Arch ones in pacman's cache, the AUR ones and the release's own in the
# ISO's local repository. mkarchiso runs with the network cut, so a name that
# is not here is a pacstrap failure fifty minutes in.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
# shellcheck source=tools/lib-manifest.sh
source "$SCRIPT_DIR/lib-manifest.sh"
PACKAGES_FILE="$PROJECT_ROOT/archiso/packages.x86_64"
OFFICIAL_CACHE="/var/cache/pacman/pkg"
AUR_REPO="${SHEDOS_ISO_REPO:-$PROJECT_ROOT/out/shedos-repo}"
RELEASE_MANIFEST="${SHEDOS_MANIFEST:-$PROJECT_ROOT/release-manifest.toml}"

# Read AUR packages from packages/aur.txt (single source of truth)
AUR_FILE="$PROJECT_ROOT/packages/aur.txt"
if [ -f "$AUR_FILE" ]; then
    mapfile -t AUR_PACKAGES < <(grep -v '^#' "$AUR_FILE" | grep -v '^$' | tr -d ' ')
else
    AUR_PACKAGES=()
fi

RELEASE_LIST=$(mktemp)
trap 'rm -f "$RELEASE_LIST"' EXIT
manifest_read "$RELEASE_MANIFEST" | awk -F'\t' '$1 == "package" { print $2 }' \
    | LC_ALL=C sort -u > "$RELEASE_LIST"

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

    # The release's own packages were fetched into the ISO repository, never
    # into pacman's cache. A name the manifest carries is looked for there and
    # nowhere else, so a missing one is reported as what it is.
    if grep -qxF "$pkg" "$RELEASE_LIST"; then
        CHECKED=$((CHECKED + 1))
        if ! ls "$AUR_REPO/${pkg}"-*.pkg.tar.zst >/dev/null 2>&1; then
            echo "MISSING (the release was not fetched): $pkg"
            MISSING=$((MISSING + 1))
        fi
        continue
    fi

    CHECKED=$((CHECKED + 1))

    # pacman's cache first, then the ISO repository, which is where the AUR
    # builds land.
    if ! ls "$OFFICIAL_CACHE/${pkg}"-*.pkg.tar.zst >/dev/null 2>&1 \
       && ! ls "$AUR_REPO/${pkg}"-*.pkg.tar.zst >/dev/null 2>&1; then
        echo "MISSING: $pkg"
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
    echo "ERROR: some packages are missing from the cache"
    echo "Run tools/download-packages.sh (and tools/fetch-packages.sh) first."
    exit 1
else
    echo ""
    echo "SUCCESS: every package is here"
    echo ""
    echo "Cache statistics:"
    echo "  Official: $(find "$OFFICIAL_CACHE" -maxdepth 1 -name '*.pkg.tar.zst' 2>/dev/null | wc -l) packages"
    echo "  ISO repo: $(find "$AUR_REPO" -maxdepth 1 -name '*.pkg.tar.zst' 2>/dev/null | wc -l) packages"
    echo "  Database: $(find "$PROJECT_ROOT/db-cache" -maxdepth 1 -name '*.db' 2>/dev/null | wc -l) files"
    exit 0
fi
