#!/bin/bash
# Generate archiso/packages.x86_64 — the LIVE ISO's package list.
# Sources: packages/official/{base,installer}.txt + 5 extras. The
# installed shedOS is pacstrapped at install time from
# repo.shedos.org/stable/x86_64/ via shedos-meta's deps (rendered by
# scripts/render-meta-depends.sh).
#
# Output is FLAT (every chosen provider explicit) — pacstrap resolves
# virtual deps (jack, qt6-multimedia-backend, etc.) by first match.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PACKAGES_DIR="$PROJECT_ROOT/packages"
OUTPUT_FILE="$PROJECT_ROOT/archiso/packages.x86_64"

echo "=========================================="
echo "Generating live-ISO package list for shedOS"
echo "=========================================="

TEMP_FILE=$(mktemp)

cat > "$TEMP_FILE" << 'EOF'
# ShedOS Live ISO Package List
#
# AUTO-GENERATED — DO NOT EDIT MANUALLY.
# Sources: packages/official/{base,installer}.txt + extras (calamares,
# hyprland, kitty, shedos-branding, shedos-keyring).
# Regenerate: scripts/generate-package-list.sh

EOF

for f in base installer; do
    file="$PACKAGES_DIR/official/$f.txt"
    [[ -f "$file" ]] || { echo "missing: $file" >&2; exit 1; }
    echo "# --- $f ---" >> "$TEMP_FILE"
    grep -v '^#' "$file" | grep -v '^$' | sort -u >> "$TEMP_FILE"
    echo "" >> "$TEMP_FILE"
done

echo "# --- live installer extras ---" >> "$TEMP_FILE"
cat >> "$TEMP_FILE" <<'EOF'
calamares
hyprland
kitty
shedos-branding
shedos-keyring
EOF

mv "$TEMP_FILE" "$OUTPUT_FILE"

TOTAL_COUNT=$(grep -v '^#' "$OUTPUT_FILE" | grep -v '^$' | wc -l)
echo ""
echo "Live ISO package list generated: $TOTAL_COUNT packages."

if [ -n "${SUDO_USER:-}" ]; then
    chown "$SUDO_USER:$(id -gn "$SUDO_USER")" "$OUTPUT_FILE"
    echo "Restored ownership to user: $SUDO_USER"
fi

echo "Output: $OUTPUT_FILE"
echo "=========================================="
