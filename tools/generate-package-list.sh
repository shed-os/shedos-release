#!/bin/bash
# Generate archiso/packages.x86_64 — the LIVE ISO's package list as a
# fully-resolved flat closure. Every transitive dependency is listed
# explicitly so pacstrap has zero virtual-provider decisions to make
# at build time, which means the offline cache (populated by
# scripts/download-packages.sh) and the live-ISO install resolve to
# the same package set.
#
# Roots = packages/official/{base,installer}.txt + 4 extras
# (calamares is appended verbatim — built locally from AUR;
# shedos-branding/shedos-keyring are appended verbatim — built
# locally from packaging/shedos-*).
#
# Requires root for `pacman -Syp` (db sync). Runs in an isolated
# tempdir so the host /var/lib/pacman is untouched. CI runs as root
# already; locally: `sudo scripts/generate-package-list.sh`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PACKAGES_DIR="$PROJECT_ROOT/packages"
OUTPUT_FILE="$PROJECT_ROOT/archiso/packages.x86_64"

LOCAL_PACKAGES=(
    calamares
    shedos-branding
    shedos-keyring
    shedos-kernel
    shedos-kernel-headers
)

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: must be run as root — pacman -Sy syncs the db." >&2
    echo "       Run: sudo $0" >&2
    exit 1
fi

echo "=========================================="
echo "Generating live-ISO package list for shedOS"
echo "=========================================="

is_local() {
    local pkg=$1
    [[ "$pkg" == shedos-* ]] && return 0
    for local_pkg in "${LOCAL_PACKAGES[@]}"; do
        [[ "$pkg" == "$local_pkg" ]] && return 0
    done
    return 1
}

ROOTS=()
for f in base installer; do
    file="$PACKAGES_DIR/official/$f.txt"
    [[ -f "$file" ]] || { echo "missing: $file" >&2; exit 1; }
    while IFS= read -r pkg; do
        [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue
        is_local "$pkg" && continue
        ROOTS+=("$pkg")
    done < "$file"
done
ROOTS+=(
    hyprland kitty
    pipewire-jack pipewire-pulse wireplumber
    waybar swaybg mako nautilus
    network-manager-applet nm-connection-editor pavucontrol
    yad
)

echo "Lean roots: ${#ROOTS[@]} packages"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT
mkdir -p "$TMPDIR/db"

cat > "$TMPDIR/pacman.conf" << 'EOF'
[options]
HoldPkg     = pacman glibc
Architecture = x86_64
SigLevel    = Never
LocalFileSigLevel = Optional

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF

echo "Syncing pacman databases into $TMPDIR/db ..."
pacman -Sy --noconfirm \
    --dbpath "$TMPDIR/db" \
    --config "$TMPDIR/pacman.conf" >/dev/null

echo "Resolving full transitive closure ..."
pacman -Sp --noconfirm \
    --dbpath "$TMPDIR/db" \
    --config "$TMPDIR/pacman.conf" \
    --print-format '%n' \
    "${ROOTS[@]}" \
    | grep -vE '^(calamares|shedos-)' \
    | sort -u > "$TMPDIR/resolved.txt"

RESOLVED_COUNT=$(wc -l < "$TMPDIR/resolved.txt")
echo "Resolved $RESOLVED_COUNT pacman-repo packages."

{
    cat << 'EOF'
# ShedOS Live ISO Package List
#
# AUTO-GENERATED — DO NOT EDIT MANUALLY.
# Source: packages/official/{base,installer}.txt + extras (hyprland,
# kitty, pipewire-jack, calamares, shedos-branding, shedos-keyring).
# Regenerate: sudo scripts/generate-package-list.sh
#
# Every transitive dep is listed explicitly so pacstrap has no
# virtual-provider rolls to do at build time. That keeps the offline
# cache (download-packages.sh) and the live-ISO install consistent.

EOF
    cat "$TMPDIR/resolved.txt"
    echo ""
    echo "# --- local repo (built into archiso/shedos-repo) ---"
    printf '%s\n' "${LOCAL_PACKAGES[@]}"
} > "$OUTPUT_FILE"

TOTAL=$(grep -cv '^#\|^$' "$OUTPUT_FILE")
echo ""
echo "Live ISO package list generated: $TOTAL packages."

if [ -n "${SUDO_USER:-}" ]; then
    chown "$SUDO_USER:$(id -gn "$SUDO_USER")" "$OUTPUT_FILE"
    echo "Restored ownership to user: $SUDO_USER"
fi

echo "Output: $OUTPUT_FILE"
echo "=========================================="
