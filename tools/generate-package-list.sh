#!/bin/bash
# Generate archiso/packages.x86_64 from packages/ directory
# This ensures a single source of truth for package management

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PACKAGES_DIR="$PROJECT_ROOT/packages"
OUTPUT_FILE="$PROJECT_ROOT/archiso/packages.x86_64"

echo "=========================================="
echo "Generating package list for shedOS"
echo "=========================================="

# Create temporary file
TEMP_FILE=$(mktemp)

# Add header
cat > "$TEMP_FILE" << 'EOF'
# ShedOS Package List
# AUTO-GENERATED - DO NOT EDIT MANUALLY
# Edit files in packages/official/ and packages/aur.txt instead
# Then run: make generate-packages

EOF

# Combine all official packages
echo "# Official Repository Packages" >> "$TEMP_FILE"
echo "# =============================" >> "$TEMP_FILE"
echo "" >> "$TEMP_FILE"

for file in "$PACKAGES_DIR"/official/*.txt; do
    if [ -f "$file" ]; then
        category=$(basename "$file" .txt)
        echo "# --- $category ---" >> "$TEMP_FILE"
        # Filter out comments and empty lines, then add packages
        grep -v '^#' "$file" | grep -v '^$' | sort -u >> "$TEMP_FILE"
        echo "" >> "$TEMP_FILE"
    fi
done

# Add AUR packages
echo "" >> "$TEMP_FILE"
echo "# AUR Packages" >> "$TEMP_FILE"
echo "# ============" >> "$TEMP_FILE"
grep -v '^#' "$PACKAGES_DIR/aur.txt" | grep -v '^$' | sort -u >> "$TEMP_FILE"

# Move to final location
mv "$TEMP_FILE" "$OUTPUT_FILE"

# Count packages
OFFICIAL_COUNT=$(find "$PACKAGES_DIR/official" -name "*.txt" -exec grep -v '^#' {} \; | grep -v '^$' | sort -u | wc -l)
AUR_COUNT=$(grep -v '^#' "$PACKAGES_DIR/aur.txt" | grep -v '^$' | wc -l)
TOTAL_COUNT=$(grep -v '^#' "$OUTPUT_FILE" | grep -v '^$' | grep -v '^---' | wc -l)

echo ""
echo "Package list generated:"
echo "  Official packages: $OFFICIAL_COUNT"
echo "  AUR packages: $AUR_COUNT"
echo "  Total unique: $TOTAL_COUNT"
echo ""
echo "Output: $OUTPUT_FILE"
echo "=========================================="
