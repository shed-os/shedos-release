#!/usr/bin/env bash
# Pre-flight: every shedos-* PKGBUILD depend must be in packages/*.txt.
# Run from `make prepare`; catches gaps in 0.2s instead of 50m into pacstrap.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGING_DIR="$PROJECT_ROOT/packaging"
SOURCES_DIR="$PROJECT_ROOT/packages"

# Pulled in transitively via `base`; never need an explicit source-list entry.
BASE_PROVIDED=(bash coreutils diffutils gcc-libs glibc systemd)

# awk-per-file (vs cat) handles source files missing trailing newlines.
sources_set() {
    {
        for f in "$SOURCES_DIR"/official/*.txt "$SOURCES_DIR"/aur.txt \
                 "$SOURCES_DIR"/.meta-closure.txt; do
            [[ -r $f ]] || continue
            awk 'NF { print } END { }' "$f"
        done
    } \
        | grep -v '^[[:space:]]*#' \
        | grep -v '^[[:space:]]*$' \
        | sort -u
}

# Known virtual providers; depend name → actual package in aur.txt.
declare -A VIRTUAL_PROVIDERS=(
    [ananicy-cpp]=ananicy-cpp-git    # -git builds against glibc 2.41+
)

extract_depends() {
    local pkgbuild=$1
    awk '/^depends=\(/,/^\)/' "$pkgbuild" \
        | grep -oE "^[[:space:]]*'[^']+'" \
        | tr -d "' "
}

main() {
    local sources missing=() pinned=()
    sources=$(sources_set)

    for pkgbuild in "$PACKAGING_DIR"/shedos-*/PKGBUILD; do
        local pkgname
        pkgname=$(awk -F= '/^pkgname=/ {print $2; exit}' "$pkgbuild")
        local deps
        deps=$(extract_depends "$pkgbuild" || true)
        [[ -z $deps ]] && continue

        while IFS= read -r dep; do
            [[ -z $dep ]] && continue
            # Match on the bare name for coverage checks below.
            local bare=${dep%%[<>=]*}
            # An '=' pin on a package ShedOS does not publish wedges
            # every update once Arch moves past it.
            if [[ $dep == "$bare="* && $bare != shedos-* ]]; then
                pinned+=("$pkgname  →  $dep")
            fi
            [[ $bare == shedos-* ]] && continue
            local in_base=0
            for b in "${BASE_PROVIDED[@]}"; do
                [[ $bare == "$b" ]] && { in_base=1; break; }
            done
            (( in_base )) && continue
            local lookup_dep=$bare
            if [[ -n "${VIRTUAL_PROVIDERS[$bare]:-}" ]]; then
                lookup_dep=${VIRTUAL_PROVIDERS[$bare]}
            fi
            if ! grep -qx "$lookup_dep" <<<"$sources"; then
                missing+=("$pkgname  →  $dep")
            fi
        done <<< "$deps"
    done

    if (( ${#pinned[@]} > 0 )); then
        echo "ERROR: exact-version depends on packages ShedOS does not publish:" >&2
        echo "" >&2
        printf '  %s\n' "${pinned[@]}" >&2
        echo "" >&2
        echo "Use an unversioned (or >=) dep and ship a rebuilt package in" >&2
        echo "lockstep instead — an '=' pin on an Arch package blocks every" >&2
        echo "update once Arch moves past the pinned version." >&2
        exit 1
    fi

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
