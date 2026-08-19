#!/usr/bin/env bash
# The fetch stage: the release manifest turned into files on disk. The channel
# here is a directory of real package tarballs under a real signed database, so
# the tools run against fixtures without a line of their own being swapped out.
#
# The fixture packages are real tarballs rather than the few bytes the manifest
# suite uses, because this is where something finally unpacks one.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
FETCH=$ROOT/tools/fetch-packages.sh
EXTRACT=$ROOT/tools/extract-package.sh

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0

ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }

check() {
    local desc=$1
    shift
    if "$@"; then ok "$desc"; else bad "$desc"; fi
}

section() { printf '\n── %s\n' "$1"; }

said() { grep -qF "$1" "$WORK/last.out"; }

# --- the fixture channel ----------------------------------------------------

export GNUPGHOME=$WORK/gnupg
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"
gpg --batch --pinentry-mode loopback --passphrase '' \
    --quick-gen-key 'ShedOS fetch harness <harness@shedos.invalid>' \
    default default never > "$WORK/gpg.log" 2>&1
FP=$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr:/ { print $10; exit }')
if [[ -z $FP ]]; then
    echo 'could not generate a harness signing key:' >&2
    cat "$WORK/gpg.log" >&2
    exit 1
fi

gpg --batch --pinentry-mode loopback --passphrase '' \
    --quick-gen-key 'ShedOS fetch decoy <decoy@shedos.invalid>' \
    default default never >> "$WORK/gpg.log" 2>&1
DECOY=$(gpg --list-keys --with-colons decoy@shedos.invalid \
    | awk -F: '/^fpr:/ { print $10; exit }')

CHANNEL=$WORK/channel
PKGS=$CHANNEL/test/x86_64
ENTRIES=$WORK/entries.tsv

reset_channel() {
    rm -rf "$CHANNEL"
    mkdir -p "$PKGS"
    : > "$ENTRIES"
}

# A package that unpacks into a file saying which package it is, so an extract
# can be told apart from an empty directory and from its neighbour.
serve() {
    local name=$1 version=$2 body=${3:-}
    local file=$name-$version-any.pkg.tar.zst
    local build=$WORK/build/$name
    rm -rf "$build"
    mkdir -p "$build/usr/lib/shedos"
    printf '%s\n' "${body:-$name $version}" > "$build/usr/lib/shedos/$name.marker"
    printf 'pkgname = %s\npkgver = %s\n' "$name" "$version" > "$build/.PKGINFO"
    bsdtar --format=gnutar -caf "$PKGS/$file" -C "$build" .PKGINFO usr
    printf '%s\t%s\t%s\t%s\n' "$name" "$version" "$file" \
        "$(sha256sum "$PKGS/$file" | cut -d' ' -f1)" >> "$ENTRIES"
}

served_sum() { awk -F'\t' -v n="$1" '$1 == n { print $4; exit }' "$ENTRIES"; }
served_file() { awk -F'\t' -v n="$1" '$1 == n { print $3; exit }' "$ENTRIES"; }

seal_channel() {
    local key=${1:-$FP} name='' version='' file='' sum=''
    rm -rf "$WORK/dbroot"
    mkdir -p "$WORK/dbroot"
    while IFS=$'\t' read -r name version file sum; do
        mkdir -p "$WORK/dbroot/$name-$version"
        {
            printf '%%FILENAME%%\n%s\n\n' "$file"
            printf '%%NAME%%\n%s\n\n' "$name"
            printf '%%VERSION%%\n%s\n\n' "$version"
            printf '%%SHA256SUM%%\n%s\n' "$sum"
        } > "$WORK/dbroot/$name-$version/desc"
    done < "$ENTRIES"
    tar czf "$PKGS/shedos.db.tar.gz" -C "$WORK/dbroot" .
    rm -f "$PKGS/shedos.db.tar.gz.sig"
    gpg --batch --yes --detach-sign --no-armor -u "$key" \
        -o "$PKGS/shedos.db.tar.gz.sig" "$PKGS/shedos.db.tar.gz" 2>> "$WORK/gpg.log"
    gpg --export "$FP" > "$CHANNEL/shedos.gpg"
}

# The repo/ref fields are the source side of a pin and the fetch stage never
# reads them, so the fixture writes shapes that parse and says so here rather
# than standing up repositories nothing will ask about.
write_manifest() {
    local out=$1
    shift
    {
        printf '[release]\nversion = "2026.08.09"\n'
        while (( $# )); do
            IFS=, read -r name pkgver pkgrel sum <<<"$1"
            printf '\n[[package]]\nname = "%s"\nrepo = "%s"\nref = "1.0"\n' "$name" "$name"
            printf 'pkgver = "%s"\npkgrel = "%s"\nsha256 = "%s"\n' "$pkgver" "$pkgrel" "$sum"
            shift
        done
    } > "$out"
}

# The cache defaults to a shared directory under TMPDIR, which is right for a
# run that fetches the release twice and wrong for a suite whose fixture
# packages are called alpha-1.0-1: a case would read the previous case's bytes.
# Each call gets a cache of its own unless the case is about the cache.
with_fixture() {
    SHEDOS_MANIFEST_CHANNEL=$PKGS \
    SHEDOS_MANIFEST_CHANNEL_ROOT=$CHANNEL \
    SHEDOS_PACKAGE_CACHE=${SHEDOS_PACKAGE_CACHE:-$WORK/nocache} \
    "$@" > "$WORK/last.out" 2>&1
}

fetch()   { with_fixture bash "$FETCH" "$@"; }
extract() { with_fixture bash "$EXTRACT" "$@"; }

DEST=$WORK/dest

reset_fixture() {
    reset_channel
    serve alpha 1.0-1
    serve beta 2.0-2
    serve gamma 2.0-1
    seal_channel
    write_manifest "$WORK/manifest.toml" \
        "alpha,1.0,1,$(served_sum alpha)" \
        "beta,2.0,2,$(served_sum beta)" \
        "gamma,2.0,1,$(served_sum gamma)"
    rm -rf "$DEST" "$WORK/cache" "$WORK/nocache"
}

# --- case 1: the whole release comes down -----------------------------------

section 'case 1 — every package the manifest names is fetched and verified'
reset_fixture
fetch "$WORK/manifest.toml" "$DEST"
rc=$?
check 'the fetch succeeds' test "$rc" -eq 0
check 'alpha is on disk'  test -f "$DEST/$(served_file alpha)"
check 'beta is on disk'   test -f "$DEST/$(served_file beta)"
check 'gamma is on disk'  test -f "$DEST/$(served_file gamma)"
check 'nothing else came with them' test 3 -eq "$(find "$DEST" -type f | wc -l)"
check 'it says what it held each package to' said "sha256=$(served_sum beta)"
check 'it counts what it wrote' said '3 package(s) into'

section 'case 1a — the bytes on disk are the bytes the manifest named'
check 'alpha hashes to its pin' \
    test "$(sha256sum "$DEST/$(served_file alpha)" | cut -d' ' -f1)" = "$(served_sum alpha)"

# --- case 2: a package the channel does not serve ---------------------------

section 'case 2 — a manifest naming a package the channel does not serve'
reset_fixture
write_manifest "$WORK/manifest.toml" \
    "alpha,1.0,1,$(served_sum alpha)" \
    "delta,3.0,1,$(printf 'd%.0s' {1..64})"
fetch "$WORK/manifest.toml" "$DEST"
rc=$?
check 'it refuses'          test "$rc" -eq 1
check 'it names the package' said 'the channel serves no delta'
check 'and writes nothing at all' test ! -d "$DEST"

# --- case 3: the channel has moved past the release -------------------------

section 'case 3 — the channel serves another version of a named package'
reset_fixture
write_manifest "$WORK/manifest.toml" "beta,2.0,1,$(served_sum beta)"
fetch "$WORK/manifest.toml" "$DEST"
rc=$?
check 'it refuses'      test "$rc" -eq 1
check 'it names both versions' said 'the channel serves beta 2.0-2 rather than 2.0-1'
check 'and writes nothing' test ! -d "$DEST"

# --- case 4: the manifest and the database disagree about the bytes ---------

section 'case 4 — the manifest names a sha the database does not record'
reset_fixture
write_manifest "$WORK/manifest.toml" "alpha,1.0,1,$(printf 'a%.0s' {1..64})"
fetch "$WORK/manifest.toml" "$DEST"
rc=$?
check 'it refuses'          test "$rc" -eq 1
check 'it names what the database records' said "the database records $(served_sum alpha)"
check 'and writes nothing' test ! -d "$DEST"

# --- case 5: the file is not what the database sealed -----------------------

section 'case 5 — the served file no longer hashes to what was sealed over it'
reset_fixture
printf 'not the alpha package at all' > "$PKGS/$(served_file alpha)"
fetch "$WORK/manifest.toml" "$DEST"
rc=$?
check 'it refuses'      test "$rc" -eq 1
check 'it says what it got' said "$(served_file alpha) hashes to"
check 'and writes nothing' test ! -d "$DEST"

# --- case 6: a database nobody can vouch for --------------------------------

section 'case 6 — a database signed by a key the channel does not publish'
reset_fixture
seal_channel "$DECOY"
fetch "$WORK/manifest.toml" "$DEST"
rc=$?
check 'it is a could-not-check rather than a did-not-hold' test "$rc" -eq 2
check 'it says why' said 'not signed by the key the channel publishes'
check 'and writes nothing' test ! -d "$DEST"

# --- case 7: the cache ------------------------------------------------------

section 'case 7 — a second fetch reads the cache rather than the channel'
reset_fixture
SHEDOS_PACKAGE_CACHE=$WORK/cache fetch "$WORK/manifest.toml" "$DEST"
check 'the first fetch came off the channel' said 'from the channel'
rm -rf "$DEST"
SHEDOS_PACKAGE_CACHE=$WORK/cache fetch "$WORK/manifest.toml" "$DEST"
rc=$?
check 'the second fetch succeeds' test "$rc" -eq 0
check 'and says it came off the cache' said 'from the cache'
check 'the package is still on disk' test -f "$DEST/$(served_file alpha)"

section 'case 7a — a cached file that is not the release is refetched'
printf 'a stale build of alpha' > "$WORK/cache/$(served_file alpha)"
rm -rf "$DEST"
SHEDOS_PACKAGE_CACHE=$WORK/cache fetch "$WORK/manifest.toml" "$DEST"
rc=$?
check 'it succeeds'  test "$rc" -eq 0
check 'the poisoned entry was refetched rather than trusted' \
    test "$(sha256sum "$DEST/$(served_file alpha)" | cut -d' ' -f1)" = "$(served_sum alpha)"
check 'and the cache holds the release now' \
    test "$(sha256sum "$WORK/cache/$(served_file alpha)" | cut -d' ' -f1)" = "$(served_sum alpha)"

# --- case 8: extracting one package -----------------------------------------

section 'case 8 — one published package unpacked'
reset_fixture
extract "$WORK/manifest.toml" beta "$WORK/tree"
rc=$?
check 'it succeeds' test "$rc" -eq 0
check 'the shipped file is there' test -f "$WORK/tree/usr/lib/shedos/beta.marker"
check 'it is that package and not its neighbour' test ! -e "$WORK/tree/usr/lib/shedos/alpha.marker"
check 'the package metadata comes with it' test -f "$WORK/tree/.PKGINFO"

section 'case 8a — extracting a name the manifest does not carry'
rm -rf "$WORK/tree2"
extract "$WORK/manifest.toml" delta "$WORK/tree2"
rc=$?
check 'it refuses'       test "$rc" -eq 1
check 'it names the package' said 'the manifest names no delta'
check 'and unpacks nothing' test ! -e "$WORK/tree2/usr"

section 'case 8b — extracting a package whose bytes moved under the database'
reset_fixture
printf 'not the beta package' > "$PKGS/$(served_file beta)"
rm -rf "$WORK/tree3"
extract "$WORK/manifest.toml" beta "$WORK/tree3"
rc=$?
check 'it refuses'        test "$rc" -eq 1
check 'and unpacks nothing' test ! -e "$WORK/tree3/usr"

# --- case 9: the live release ----------------------------------------------

section 'case 9 — the committed manifest against the live channel'
if [[ ${SHEDOS_SKIP_LIVE:-0} == 1 ]]; then
    printf '  skip live channel read (SHEDOS_SKIP_LIVE)\n'
elif ! curl -sS -I -m 20 https://repo.shedos.org/staging/test/x86_64/shedos.db.tar.gz \
        > /dev/null 2>&1; then
    printf '  skip live channel read (channel unreachable)\n'
else
    rm -rf "$WORK/live"
    bash "$FETCH" "$ROOT/release-manifest.toml" "$WORK/live" > "$WORK/last.out" 2>&1
    rc=$?
    check 'every pin in the committed manifest fetches and verifies' test "$rc" -eq 0
    check 'and the release is nineteen packages' said '19 package(s) into'
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
