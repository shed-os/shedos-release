#!/bin/bash
# Generate archiso/packages.x86_64; the airootfs package list.
#
# airootfs IS the developer install (Calamares unpackfs copies it onto
# /target). So packages.x86_64 must contain the FULL system: every
# category in packages/official/*.txt + every entry in packages/aur.txt
# (which already includes aur-norepublish proprietaries) + shedos-meta
# (pulls every shedos-* via depends=()).
#
# Format: flat resolved closure. Every chosen virtual provider lives at
# the root of pacman's resolution graph so pacstrap doesn't auto-pick the
# wrong one (jack2 vs pipewire-jack, iptables-legacy vs iptables, etc.).
#
# Requires root (pacman -Sy syncs the temp db).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PACKAGES_DIR="$PROJECT_ROOT/packages"
OUTPUT_FILE="$PROJECT_ROOT/archiso/packages.x86_64"

# shedos-* + AUR packages live in [shedos-repo] (file://archiso/shedos-repo)
# at build time. They're appended verbatim to packages.x86_64; pacstrap
# picks them up via the build-time pacman.conf which has [shedos-repo].
LOCAL_PACKAGES=(
    calamares
    shedos-branding
    shedos-keyring
    shedos-meta
    shedos-kernel
    shedos-kernel-headers
)

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: must be run as root" >&2
    exit 1
fi

is_local() {
    local pkg=$1
    [[ "$pkg" == shedos-* ]] && return 0
    for local_pkg in "${LOCAL_PACKAGES[@]}"; do
        [[ "$pkg" == "$local_pkg" ]] && return 0
    done
    return 1
}

ROOTS=()

# Every category in packages/official/. Skip local entries; appended below.
for f in "$PACKAGES_DIR"/official/*.txt; do
    [[ -f $f ]] || continue
    while IFS= read -r pkg; do
        [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue
        is_local "$pkg" && continue
        ROOTS+=("$pkg")
    done < "$f"
done

# Every AUR entry (republishable + aur-norepublish). aur-norepublish entries
# are NOT pushed to repo.shedos.org R2 (build-packages.yml lines 384-391
# skip them) but they ARE in archiso/shedos-repo locally, so pacstrap can
# pull them at ISO build time → they end up in airootfs → unpackfs copies
# them to the installed system. This is how the 4 vendor proprietaries
# (chrome, postman, claude-code-bin, jetbrains-toolbox) plus the other 4
# (vscode, slack, obsidian, ms-fonts) install during Calamares offline.
AUR_FILE="$PACKAGES_DIR/aur.txt"
if [[ -f $AUR_FILE ]]; then
    while IFS= read -r pkg; do
        [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue
        pkg=${pkg%%[[:space:]]*}
        is_local "$pkg" && continue
        ROOTS+=("$pkg")
    done < "$AUR_FILE"
fi

echo "Roots: ${#ROOTS[@]} packages (before transitive resolution)"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT
mkdir -p "$TMPDIR/db"

# Same shape as the build-time pacman.conf (archiso/pacman.conf.in) so the
# resolved closure matches what mkarchiso pacstrap will actually see. We
# don't include [shedos-repo] here because resolve closure for *Arch*
# packages only; local-repo packages get appended verbatim below and
# pacstrap resolves their deps at build time.
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

pacman -Sy --noconfirm --dbpath "$TMPDIR/db" --config "$TMPDIR/pacman.conf" >/dev/null

# Resolve the official-repo closure. AUR + shedos-* roots aren't in core/
# extra/multilib so pacman -Sp would error on them; filter them out of
# the root list before resolution.
ARCH_ROOTS=()
for r in "${ROOTS[@]}"; do
    is_local "$r" && continue
    # AUR entries are also out-of-Arch-repo; skip if pacman doesn't know.
    if pacman -Si --dbpath "$TMPDIR/db" --config "$TMPDIR/pacman.conf" "$r" >/dev/null 2>&1; then
        ARCH_ROOTS+=("$r")
    fi
done

pacman -Sp --noconfirm \
    --dbpath "$TMPDIR/db" \
    --config "$TMPDIR/pacman.conf" \
    --print-format '%n' \
    "${ARCH_ROOTS[@]}" \
    | grep -vE '^(calamares|shedos-)' \
    | sort -u > "$TMPDIR/resolved.txt"

# AUR entries (and local shedos-* not already in LOCAL_PACKAGES) get
# appended literally; pacstrap finds them via [shedos-repo] (file://).
AUR_LITERAL=()
for r in "${ROOTS[@]}"; do
    is_local "$r" && continue
    if ! pacman -Si --dbpath "$TMPDIR/db" --config "$TMPDIR/pacman.conf" "$r" >/dev/null 2>&1; then
        AUR_LITERAL+=("$r")
    fi
done

{
    cat << 'EOF'
# ShedOS airootfs package list
#
# AUTO-GENERATED; DO NOT EDIT MANUALLY.
# Source: packages/official/*.txt + packages/aur.txt
# Regenerate: sudo scripts/generate-package-list.sh
#
# Flat resolved closure. Every transitive dep is listed explicitly so
# pacstrap has no virtual-provider rolls to do at build time.

EOF
    cat "$TMPDIR/resolved.txt"
    echo ""
    echo "# --- AUR (built into archiso/shedos-repo by build-aur-packages.sh) ---"
    printf '%s\n' "${AUR_LITERAL[@]}" | LC_ALL=C sort -u
    echo ""
    echo "# --- shedos-* + calamares (built into archiso/shedos-repo) ---"
    printf '%s\n' "${LOCAL_PACKAGES[@]}"
} > "$OUTPUT_FILE"

if [ -n "${SUDO_USER:-}" ]; then
    chown "$SUDO_USER:$(id -gn "$SUDO_USER")" "$OUTPUT_FILE"
fi

TOTAL=$(grep -cv '^#\|^$' "$OUTPUT_FILE")
RESOLVED=$(wc -l < "$TMPDIR/resolved.txt")
echo "Wrote $OUTPUT_FILE ($TOTAL packages: $RESOLVED Arch + ${#AUR_LITERAL[@]} AUR + ${#LOCAL_PACKAGES[@]} local)"
