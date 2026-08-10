#!/usr/bin/env bash
# A carved repo and the monolith directory it was carved from hold the same
# PKGBUILD, and nothing in the pipeline compares the two. A carve taken from a
# source tree that had fallen behind ships an old pkgver with every gate green:
# the suites pass, the build works, the publisher takes it, and the equivalence
# check builds its reference from the same stale tree the candidate came from,
# so the two agree about the wrong version. This is what notices.
#
# SHEDOS_PARITY_PAIRS, SHEDOS_PARITY_CARVED_DIR and SHEDOS_PARITY_MONOLITH_DIR
# replace the list and the two fetches, which is how the cases below run offline.
set -uo pipefail

MONOLITH_RAW=https://raw.githubusercontent.com/Theshedman/shedos/main
CARVED_RAW=https://raw.githubusercontent.com/shed-os
# Cloudflare's managed rules drop datacenter traffic that does not name itself,
# and a GitHub runner is a datacenter address.
USER_AGENT='shedos-release (+https://shedos.org)'

# Each carved repo and the directory it came out of. One more line per carve,
# and the whole list goes at cutover when the monolith stops holding packaging.
PAIRS='cage packaging/cage
shedos-nvim packaging/shedos-nvim
shedos-migrate packaging/shedos-migrate-to-packaged
shedos-keyring packaging/shedos-keyring'

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0

ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }
not() { ! "$@"; }

check() {
    local desc=$1
    shift
    if "$@"; then ok "$desc"; else bad "$desc"; fi
}

section() { printf '\n── %s\n' "$1"; }

# --- the check --------------------------------------------------------------

# Read, never sourced: a PKGBUILD is a shell script and these come off the
# network. An empty answer is refused rather than compared, or a pkgver built in
# a pkgver() function would read as empty on both sides and match.
pkgbuild_field() {
    local value
    value=$(sed -n "s/^$2=//p" "$1" | head -1 | tr -d "\"'")
    [[ -n $value ]] || return 1
    printf '%s\n' "$value"
}

read_pkgbuild() {
    local dir=$1 key=$2 url=$3 out=$4
    if [[ -n $dir ]]; then
        cp -- "$dir/$key/PKGBUILD" "$out" 2>/dev/null
    else
        curl -sSfL --max-time 60 -A "$USER_AGENT" -o "$out" "$url"
    fi
}

# 0 every pair agrees, 1 one of them has diverged, 2 a PKGBUILD could not be read.
parity_check() {
    local pairs repo path carved monolith cver crel mver mrel
    local seen=0 diverged=0
    carved=$WORK/carved.PKGBUILD
    monolith=$WORK/monolith.PKGBUILD
    pairs=${SHEDOS_PARITY_PAIRS:-$PAIRS}

    while read -r repo path; do
        [[ -n ${repo//[[:space:]]/} ]] || continue
        seen=$((seen + 1))

        read_pkgbuild "${SHEDOS_PARITY_CARVED_DIR:-}" "$repo" \
            "$CARVED_RAW/$repo/main/PKGBUILD" "$carved" \
            || { echo "could not read the PKGBUILD in $repo"; return 2; }
        read_pkgbuild "${SHEDOS_PARITY_MONOLITH_DIR:-}" "$path" \
            "$MONOLITH_RAW/$path/PKGBUILD" "$monolith" \
            || { echo "could not read the PKGBUILD in $path"; return 2; }

        if ! cver=$(pkgbuild_field "$carved" pkgver) ||
                ! crel=$(pkgbuild_field "$carved" pkgrel); then
            echo "$repo names no pkgver or pkgrel"
            return 2
        fi
        if ! mver=$(pkgbuild_field "$monolith" pkgver) ||
                ! mrel=$(pkgbuild_field "$monolith" pkgrel); then
            echo "$path names no pkgver or pkgrel"
            return 2
        fi

        # pkgver has to match. pkgrel may run ahead, because the pipeline bumps it
        # past whatever the channel already carries every time it republishes.
        if [[ $cver != "$mver" ]]; then
            echo "$repo is at $cver-$crel and $path is at $mver-$mrel"
            diverged=1
        elif (( $(vercmp "$crel" "$mrel") < 0 )); then
            echo "$repo is at $cver-$crel behind $path at $mver-$mrel"
            diverged=1
        fi
    done <<<"$pairs"

    (( seen > 0 )) || { echo 'no carved repositories to compare'; return 2; }
    (( diverged == 0 )) || return 1
    printf 'all %d carved package(s) are at the monolith version\n' "$seen"
}

run_check() {
    (
        unset SHEDOS_PARITY_PAIRS SHEDOS_PARITY_CARVED_DIR SHEDOS_PARITY_MONOLITH_DIR
        while (( $# )); do export "${1?}"; shift; done
        parity_check
    ) >"$WORK/last.out" 2>&1
}

# --- fixtures ---------------------------------------------------------------

CARVED=$WORK/fixture/carved
MONO=$WORK/fixture/monolith
TWO='alpha packaging/alpha
beta packaging/beta'

write_pkgbuild() {
    local out=$1/PKGBUILD
    mkdir -p "$1"
    {
        echo 'pkgname=example'
        echo "pkgver=$2"
        echo "pkgrel=$3"
        echo "arch=('any')"
    } > "$out"
}

set_pair() {
    write_pkgbuild "$CARVED/$1" "$3" "$4"
    write_pkgbuild "$MONO/$2" "$5" "$6"
}

with_fixtures() {
    run_check "SHEDOS_PARITY_PAIRS=$TWO" \
        "SHEDOS_PARITY_CARVED_DIR=$CARVED" "SHEDOS_PARITY_MONOLITH_DIR=$MONO"
}

reset_fixtures() {
    rm -rf "$WORK/fixture"
    set_pair alpha packaging/alpha 1.0 1 1.0 1
    set_pair beta packaging/beta 2026.08.09 1 2026.08.09 1
}

# --- case 1: the versions match ---------------------------------------------

section 'case 1 — every carved package at the monolith version passes'
reset_fixtures
with_fixtures
rc=$?
check 'the check passes' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/last.out"
check 'it says how many it compared' \
    grep -qx 'all 2 carved package(s) are at the monolith version' "$WORK/last.out"

# --- case 2: pkgver diverged ------------------------------------------------

section 'case 2 — a carved package left behind on an older pkgver is refused'
reset_fixtures
set_pair beta packaging/beta 2026.07.03 1 2026.08.09 1
with_fixtures
check 'the check fails' test "$?" -eq 1
check 'it names the repo and both versions' \
    grep -qx 'beta is at 2026.07.03-1 and packaging/beta is at 2026.08.09-1' "$WORK/last.out"
check 'the pair that agrees is not reported' not grep -q '^alpha ' "$WORK/last.out"

# --- case 3: pkgrel behind --------------------------------------------------

section 'case 3 — a carved pkgrel behind the monolith is refused'
reset_fixtures
set_pair beta packaging/beta 2026.08.09 2 2026.08.09 5
with_fixtures
check 'the check fails' test "$?" -eq 1
check 'it names the repo and both versions' \
    grep -qx 'beta is at 2026.08.09-2 behind packaging/beta at 2026.08.09-5' "$WORK/last.out"

# --- case 4: pkgrel ahead ---------------------------------------------------

section 'case 4 — a carved pkgrel ahead of the monolith is fine'
reset_fixtures
set_pair beta packaging/beta 2026.08.09 6 2026.08.09 2
with_fixtures
rc=$?
check 'the check passes' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/last.out"
check 'nothing is reported' not grep -q ' behind ' "$WORK/last.out"

# --- case 5: a PKGBUILD that is not there -----------------------------------

section 'case 5 — a PKGBUILD that cannot be read stops the check'
reset_fixtures
rm -rf "$CARVED/beta"
with_fixtures
check 'the check fails' test "$?" -eq 2
check 'it says which side' grep -qx 'could not read the PKGBUILD in beta' "$WORK/last.out"

# --- case 6: a version that is not written down -----------------------------

section 'case 6 — a pkgver the PKGBUILD computes is not read as a match'
reset_fixtures
printf 'pkgname=example\npkgrel=1\npkgver() { echo 1.0; }\n' > "$CARVED/beta/PKGBUILD"
printf 'pkgname=example\npkgrel=1\npkgver() { echo 1.0; }\n' > "$MONO/packaging/beta/PKGBUILD"
with_fixtures
check 'the check fails' test "$?" -eq 2
check 'it says the version is not there' grep -qx 'beta names no pkgver or pkgrel' "$WORK/last.out"

# --- case 7: the carves as they stand ---------------------------------------

section 'case 7 — every carved repository matches the monolith it came from'
run_check
rc=$?
check 'the check passes' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/last.out"

# --- result -----------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
