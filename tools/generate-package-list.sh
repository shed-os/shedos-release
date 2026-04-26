#!/bin/bash
# Generate archiso/packages.x86_64 from packages/ directory.
#
# Why packages.x86_64 is the flat list (every package explicit):
#
# An earlier design collapsed this file to "shedos-meta + essentials" and
# let shedos-meta's depends=() pull in everything transitively. That caused
# pacstrap provider-pick bugs: when a package has depends=('jack') and both
# jack2 and pipewire-jack provide 'jack', pacman (--noconfirm) picks the
# alphabetical default (jack2) BEFORE it descends into shedos-meta.depends
# where we'd listed pipewire-jack — so both end up in the resolution set
# and explode as an unresolvable conflict. Same story for VIRTUALBOX-HOST-
# MODULES (we want -arch, pacman defaults to -dkms), etc.
#
# The fix: every chosen provider lives at the ROOT of the resolution graph
# (i.e., explicit in packages.x86_64). Pacman sees them first → no
# ambiguity. That's the whole reason this file is long.
#
# Packages excluded from the list:
#   - packages/aur-norepublish.txt (proprietary AUR: vscode, chrome, slack,
#     obsidian, postman, ms-fonts). These stay as optdepends on shedos-meta
#     and install via yay/shedos-welcome, not pacstrap.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PACKAGES_DIR="$PROJECT_ROOT/packages"
OUTPUT_FILE="$PROJECT_ROOT/archiso/packages.x86_64"

echo "=========================================="
echo "Generating package list for shedOS"
echo "=========================================="

TEMP_FILE=$(mktemp)

cat > "$TEMP_FILE" << 'EOF'
# ShedOS Package List
#
# AUTO-GENERATED — DO NOT EDIT MANUALLY.
#   source of truth: packages/official/*.txt + packages/aur.txt
#   excluded:        packages/aur-norepublish.txt (proprietary — stays as
#                    optdepends on shedos-meta)
#   regenerate with: scripts/generate-package-list.sh
#
# This is the FLAT list by design. Every chosen provider must be explicit
# at the root of pacman's resolution graph or pacstrap will auto-pick the
# wrong provider when resolving a virtual dep (`jack`, VIRTUALBOX-HOST-
# MODULES, qt6-multimedia-backend, …) and the chosen provider will
# collide with the default when the latter is finally pulled in
# transitively.

EOF

# Official repo packages (all categories).
echo "# Official Repository Packages" >> "$TEMP_FILE"
echo "# =============================" >> "$TEMP_FILE"
echo "" >> "$TEMP_FILE"

for file in "$PACKAGES_DIR"/official/*.txt; do
    if [ -f "$file" ]; then
        category=$(basename "$file" .txt)
        echo "# --- $category ---" >> "$TEMP_FILE"
        grep -v '^#' "$file" | grep -v '^$' | sort -u >> "$TEMP_FILE"
        echo "" >> "$TEMP_FILE"
    fi
done

# AUR packages MINUS proprietary (aur-norepublish.txt).
# Proprietary ones are still pacstrap-able in principle, but legally we
# won't republish their binaries via [shedos]; keeping them out of
# packages.x86_64 means they also don't land on the ISO itself, which
# matches the "shedos-welcome offers proprietary installs post-boot" UX.
NOREPUB="$PACKAGES_DIR/aur-norepublish.txt"
AUR_LIST=$(mktemp)
REPUB_LIST=$(mktemp)
grep -v '^#' "$PACKAGES_DIR/aur.txt" | grep -v '^$' | awk '{print $1}' | sort -u > "$AUR_LIST"
if [ -f "$NOREPUB" ]; then
    grep -Fxvf <(grep -v '^#' "$NOREPUB" | grep -v '^$' | awk '{print $1}') \
        "$AUR_LIST" > "$REPUB_LIST"
else
    cp "$AUR_LIST" "$REPUB_LIST"
fi

echo "" >> "$TEMP_FILE"
echo "# AUR Packages (republishable only; proprietary ones in" >> "$TEMP_FILE"
echo "# aur-norepublish.txt stay as optdepends on shedos-meta)" >> "$TEMP_FILE"
echo "# ============" >> "$TEMP_FILE"
cat "$REPUB_LIST" >> "$TEMP_FILE"

# ShedOS native packages. shedos-keyring sets up pacman-key trust for
# the [shedos] repo at first boot; shedos-meta's install hooks wire up
# services and append [shedos] to /etc/pacman.conf. shedos-meta's
# depends=() is also what pulls in individual shedos-* packages.
echo "" >> "$TEMP_FILE"
echo "# ShedOS Native Packages" >> "$TEMP_FILE"
echo "# ======================" >> "$TEMP_FILE"
echo "shedos-keyring" >> "$TEMP_FILE"
echo "shedos-meta" >> "$TEMP_FILE"

mv "$TEMP_FILE" "$OUTPUT_FILE"

OFFICIAL_COUNT=$(find "$PACKAGES_DIR/official" -name "*.txt" -exec grep -v '^#' {} \; | grep -v '^$' | sort -u | wc -l)
AUR_ALL=$(wc -l < "$AUR_LIST")
AUR_REPUB=$(wc -l < "$REPUB_LIST")
AUR_EXCLUDED=$(( AUR_ALL - AUR_REPUB ))
TOTAL_COUNT=$(grep -v '^#' "$OUTPUT_FILE" | grep -v '^$' | wc -l)
rm -f "$AUR_LIST" "$REPUB_LIST"

echo ""
echo "Package list generated:"
echo "  Official packages:           $OFFICIAL_COUNT"
echo "  AUR (republishable):         $AUR_REPUB"
echo "  AUR (excluded, proprietary): $AUR_EXCLUDED"
echo "  Total explicit in ISO:       $TOTAL_COUNT"
echo ""
if [ -n "$SUDO_USER" ]; then
    chown "$SUDO_USER:$(id -gn "$SUDO_USER")" "$OUTPUT_FILE"
    echo "Restored ownership to user: $SUDO_USER"
fi

echo "Output: $OUTPUT_FILE"
echo "=========================================="
