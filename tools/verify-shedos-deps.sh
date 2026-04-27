#!/usr/bin/env bash
# verify-shedos-deps.sh — fail fast if any shedos-* PKGBUILD declares a
# direct depends=() entry that isn't covered by packages/official/*.txt
# or packages/aur.txt.
#
# Why: pacstrap reads archiso/packages.x86_64 (auto-generated from those
# source lists). If a shedos-* package depends on `zram-generator` but
# `zram-generator` isn't in any source list, pacstrap fails ~50 minutes
# into the ISO build with "Package not in cache". This script reproduces
# that check in 0.2 s before any heavy lifting starts.
#
# Coverage:
#   - All packaging/shedos-*/PKGBUILD files
#   - depends=() only (makedepends are install-time-only on the build
#     host, not present on the live ISO)
#   - Internal shedos-* deps are skipped (they're built by us, registered
#     into archiso/shedos-repo by build-shedos-packages.sh)
#   - Toolchain virtual-deps already in `base` (bash, coreutils,
#     diffutils, gcc-libs, systemd) are skipped — pacstrap pulls them
#     transitively via base, listed here as a tight allowlist
#
# Exits 0 on clean, 1 on any missing dep with a list of what to add and
# where it came from.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGING_DIR="$PROJECT_ROOT/packaging"
SOURCES_DIR="$PROJECT_ROOT/packages"

# Packages provided transitively by `base` in the ISO. Pacstrap pulls
# them via base (which IS in packages/official/base.txt), so a shedos-*
# PKGBUILD listing them is fine even if no source list mentions them.
BASE_PROVIDED=(bash coreutils diffutils gcc-libs glibc systemd)

# Build the source-list set: every non-comment, non-blank line from
# packages/official/*.txt + packages/aur.txt.
#
# Defensive against missing trailing newlines: a source file that ends
# without LF would glue its last entry to the next file's first line
# under plain `cat`. We force-end each file with a newline by feeding
# them through awk's END { print "" } per-file equivalent: read with a
# loop and printf %s\n.
sources_set() {
    {
        for f in "$SOURCES_DIR"/official/*.txt "$SOURCES_DIR"/aur.txt; do
            [[ -r $f ]] || continue
            awk 'NF { print } END { }' "$f"
            # awk treats the final line as a record even without LF, so
            # this loop reliably emits one entry per line regardless of
            # the file's trailing-newline state.
        done
    } \
        | grep -v '^[[:space:]]*#' \
        | grep -v '^[[:space:]]*$' \
        | sort -u
}

# Virtual-provider allowlist: depend → provider-actually-in-aur.txt.
# We don't carry local PKGBUILDs for most AUR packages, so we can't
# auto-discover `provides=` from them. Encode the known cases.
declare -A VIRTUAL_PROVIDERS=(
    [ananicy-cpp]=ananicy-cpp-git    # -git variant builds against
                                     # glibc 2.41+; provides=conflicts=
                                     # ananicy-cpp upstream.
)

# Extract depends=() entries from a single PKGBUILD. Skips comment lines
# inside the array.
extract_depends() {
    local pkgbuild=$1
    awk '/^depends=\(/,/^\)/' "$pkgbuild" \
        | grep -oE "^[[:space:]]*'[^']+'" \
        | tr -d "' "
}

main() {
    local sources missing=()
    sources=$(sources_set)

    for pkgbuild in "$PACKAGING_DIR"/shedos-*/PKGBUILD; do
        local pkgname
        pkgname=$(awk -F= '/^pkgname=/ {print $2; exit}' "$pkgbuild")
        local deps
        deps=$(extract_depends "$pkgbuild" || true)
        [[ -z $deps ]] && continue

        while IFS= read -r dep; do
            [[ -z $dep ]] && continue
            # Skip internal shedos-* deps.
            [[ $dep == shedos-* ]] && continue
            # Skip base-provided toolchain.
            local in_base=0
            for b in "${BASE_PROVIDED[@]}"; do
                [[ $dep == "$b" ]] && { in_base=1; break; }
            done
            (( in_base )) && continue
            # Virtual-provider rewrite: ananicy-cpp → ananicy-cpp-git.
            local lookup_dep=$dep
            if [[ -n "${VIRTUAL_PROVIDERS[$dep]:-}" ]]; then
                lookup_dep=${VIRTUAL_PROVIDERS[$dep]}
            fi
            # Source-list lookup.
            if ! grep -qx "$lookup_dep" <<<"$sources"; then
                missing+=("$pkgname  →  $dep")
            fi
        done <<< "$deps"
    done

    if (( ${#missing[@]} > 0 )); then
        echo "ERROR: $(printf '%s\n' "${missing[@]}" | wc -l) shedos-* depends not covered by source lists:" >&2
        echo "" >&2
        printf '  %s\n' "${missing[@]}" >&2
        echo "" >&2
        echo "Add each missing package to the appropriate file under" >&2
        echo "  packages/official/*.txt   (extra/core/multilib package)" >&2
        echo "  packages/aur.txt          (AUR package)" >&2
        echo "" >&2
        echo "Then run scripts/generate-package-list.sh (or any \`make iso\`" >&2
        echo "target — generate-packages is now a Makefile prereq)." >&2
        exit 1
    fi

    echo "OK: every shedos-* PKGBUILD depend is covered by packages/."
}

main "$@"
