#!/usr/bin/env bash
# What the reference build works out before it builds anything: which monolith
# directory holds the package, where the tree has to sit, what has to sit
# beside it, and which of the environment the candidate recorded this machine
# would get wrong. Every case here runs the real script against a fixture
# monolith and a hand-written candidate package, offline and unprivileged —
# SHEDOS_REFERENCE_* replaces the two fetches, the container probe and the
# archive.
#
# The end-to-end case is the one that cannot be faked: it rebuilds a published
# package's reference and checks it against the sha the expectation file pins.
# It needs docker and the monolith, so it says what is missing and skips.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
BUILD_REFERENCE=$ROOT/tools/build-reference.sh

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

# --- fixtures ---------------------------------------------------------------

MONO=$WORK/monolith
MAPS=$WORK/maps
EXPECTED=$WORK/expected-diffs
CARVED=$WORK/carved
ARCHIVE=$WORK/archive
RUN=$WORK/run

# The candidate the fixture cases build a reference for: one binary, and a
# .BUILDINFO carrying the three things the script reads out of it — where the
# pipeline built, what makepkg was configured with, and what was installed.
write_candidate() {
    local out=$1 pkgname=$2 pkgver=$3 builddir=$4
    shift 4
    local dir=$WORK/cand
    rm -rf "$dir"
    mkdir -p "$dir/usr/bin"
    printf 'alpha\n' > "$dir/usr/bin/alpha"
    {
        echo "pkgname = $pkgname"
        echo "pkgver = $pkgver"
        echo 'pkgdesc = a fixture'
        echo 'builddate = 1700000000'
        echo 'size = 6'
        echo 'arch = x86_64'
    } > "$dir/.PKGINFO"
    {
        echo 'format = 2'
        echo "pkgname = $pkgname"
        echo "pkgver = $pkgver"
        echo 'pkgarch = x86_64'
        echo 'builddate = 1700000000'
        echo "builddir = $builddir"
        echo "startdir = $builddir"
        echo 'buildenv = !check'
        echo 'buildenv = !sign'
        echo 'options = strip'
        echo 'options = !debug'
        printf 'installed = %s\n' "$@"
    } > "$dir/.BUILDINFO"
    bsdtar --format=gnutar -C "$dir" -caf "$out" .PKGINFO .BUILDINFO usr
}

write_monolith() {
    rm -rf "$MONO"
    mkdir -p "$MONO/packaging/alpha/src" "$MONO/packaging/alphalib/src" \
        "$MONO/packaging/alpha/inner"
    cat > "$MONO/packaging/alpha/PKGBUILD" <<'EOF'
pkgname=alpha
pkgver=1.0
pkgrel=1
arch=('x86_64')
depends=('glibc')
makedepends=('cargo')
build() {
    cd "$startdir"
    cargo build --release --locked
}
package() {
    install -Dm755 "$startdir/target/release/alpha" "$pkgdir/usr/bin/alpha"
}
EOF
    cat > "$MONO/packaging/alpha/Cargo.toml" <<'EOF'
[package]
name = "alpha"

[dependencies]
alphalib = { path = "../alphalib" }
inner = { path = "inner" }

[dev-dependencies]
alphatest = { path = "../alphatest" }
EOF
    printf '[package]\nname = "alphalib"\n' > "$MONO/packaging/alphalib/Cargo.toml"
    printf '[package]\nname = "inner"\n' > "$MONO/packaging/alpha/inner/Cargo.toml"
    mkdir -p "$MONO/packaging/alphatest"
    printf '[package]\nname = "alphatest"\n' > "$MONO/packaging/alphatest/Cargo.toml"
    printf 'committed\n' > "$MONO/packaging/alpha/src/main.rs"

    mkdir -p "$MONO/packaging/beta"
    cat > "$MONO/packaging/beta/PKGBUILD" <<'EOF'
pkgname=beta
pkgver=2.0
pkgrel=1
arch=('x86_64')
depends=('glibc')
makedepends=('meson')
build() {
    meson setup "$srcdir/beta-$pkgver" build
    meson compile -C build
}
package() {
    meson install -C build --destdir "$pkgdir"
}
EOF

    git -C "$MONO" init -q -b main
    commit_monolith 'the fixture'
}

commit_monolith() {
    git -C "$MONO" -c user.email=t@t -c user.name=t add -A
    git -C "$MONO" -c user.email=t@t -c user.name=t commit -qm "$1"
}

# The carved repo the candidate came from: it fetches its own source, so where
# the build runs is a directory under $srcdir that only this file names.
write_carved() {
    local body=${1:-'cd "$srcdir/demo/alpha"'}
    rm -rf "$CARVED"
    mkdir -p "$CARVED/demo/alpha"
    {
        echo 'pkgname=alpha'
        echo 'pkgver=1.0'
        echo 'pkgrel=2'
        echo 'source=("git+https://github.com/shed-os/demo.git")'
        echo 'build() {'
        echo "    $body"
        echo '    cargo build --release --locked'
        echo '}'
    } > "$CARVED/demo/alpha/PKGBUILD"
}

write_carved_beta() {
    mkdir -p "$CARVED/beta"
    {
        echo 'pkgname=beta'
        echo 'pkgver=2.0'
        echo 'pkgrel=1'
        echo 'source=("https://example.invalid/beta-2.0.tar.gz")'
        echo 'build() {'
        echo '    meson setup "$srcdir/beta-$pkgver" build'
        echo '    meson compile -C build'
        echo '}'
    } > "$CARVED/beta/PKGBUILD"
}

write_maps() {
    rm -rf "$MAPS" "$EXPECTED"
    mkdir -p "$MAPS" "$EXPECTED"
    printf '%s\n' 'path packaging/alpha/' 'rename packaging/alpha:alpha' \
        'path packaging/alphalib/' 'rename packaging/alphalib:alphalib' > "$MAPS/demo.paths"
    printf '%s\n' 'flatten packaging/beta' > "$MAPS/beta.paths"
}

# What the container would answer with, and what the archive would serve.
write_environment() {
    rm -rf "$ARCHIVE"
    mkdir -p "$ARCHIVE/b/binutils"
    printf 'not really a package\n' \
        > "$ARCHIVE/b/binutils/binutils-2.47-1-x86_64.pkg.tar.zst"
    printf '%s\n' glibc-2.44-1-x86_64 binutils-2.48-1-x86_64 cargo-1.97.1-1-x86_64 \
        > "$WORK/installed"
}

reset_fixtures() {
    write_monolith
    write_maps
    write_carved
    write_carved_beta
    write_environment
    write_candidate "$WORK/alpha.pkg.tar.zst" alpha 1.0-2 /__w/demo/demo/alpha \
        glibc-2.44-1-x86_64 binutils-2.47-1-x86_64 pam-1.7.1-1-x86_64
}

# Run the script over the fixtures, planning only. Output lands in $WORK/out.
plan() {
    rm -rf "$RUN"
    env SHEDOS_REFERENCE_MAPS_DIR="$MAPS" SHEDOS_REFERENCE_EXPECTED_DIR="$EXPECTED" \
        SHEDOS_REFERENCE_CARVED_DIR="$CARVED" \
        SHEDOS_REFERENCE_INSTALLED="$WORK/installed" \
        SHEDOS_REFERENCE_ARCHIVE="file://$ARCHIVE" \
        SHEDOS_REFERENCE_DIR="$RUN" SHEDOS_REFERENCE_DRY_RUN=1 \
        bash "$BUILD_REFERENCE" "$@" > "$WORK/out" 2>&1
}

says() { grep -qF "$1" "$WORK/out"; }
says_line() { grep -qxF "$1" "$WORK/out"; }

# --- case 1: the arguments --------------------------------------------------

section 'case 1 — the script says what it takes'
reset_fixtures
plan
check 'no arguments is refused' test "$?" -eq 2
check 'it prints the usage' says 'usage: build-reference.sh'

plan "$MONO" "$WORK/nothing.pkg.tar.zst"
check 'a candidate that is not there is refused' test "$?" -eq 2
check 'it names the file' says "$WORK/nothing.pkg.tar.zst does not exist"

plan "$WORK/notarepo" "$WORK/alpha.pkg.tar.zst"
check 'a monolith that is not a repository is refused' test "$?" -eq 2
check 'it says so' says 'is not a git repository'

# --- case 2: which monolith directory builds the package --------------------

section 'case 2 — the carve maps say where the package comes from'
reset_fixtures
plan "$MONO" "$WORK/alpha.pkg.tar.zst"
rc=$?
check 'the plan is made' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/out"
check 'it names the packaging directory' says 'source   packaging/alpha at '
check 'it names the carved repository the candidate came from' says 'carved   demo/alpha'

reset_fixtures
write_candidate "$WORK/nope.pkg.tar.zst" nope 1.0-2 /__w/demo/demo/alpha
plan "$MONO" "$WORK/nope.pkg.tar.zst"
check 'a package no maps file names is refused' test "$?" -eq 2
check 'it names the package' says 'building nope'

# --- case 3: the versions have to agree -------------------------------------

section 'case 3 — a candidate the monolith has moved past is refused'
reset_fixtures
write_candidate "$WORK/old.pkg.tar.zst" alpha 0.9-2 /__w/demo/demo/alpha \
    glibc-2.44-1-x86_64
plan "$MONO" "$WORK/old.pkg.tar.zst"
check 'the plan is refused' test "$?" -eq 2
check 'it names both versions' says 'the candidate is alpha 0.9 and packaging/alpha is at 1.0'

# --- case 4: where the build has to run -------------------------------------

section 'case 4 — the build path is the candidate builddir plus the carved cd'
reset_fixtures
plan "$MONO" "$WORK/alpha.pkg.tar.zst"
check 'the crate sits where the pipeline put it' \
    says 'crate    /__w/demo/demo/alpha/src/demo/alpha'

reset_fixtures
write_carved 'cd "${srcdir}/demo/alpha"'
plan "$MONO" "$WORK/alpha.pkg.tar.zst"
check 'the braced form is the same path' says 'crate    /__w/demo/demo/alpha/src/demo/alpha'

reset_fixtures
write_carved 'cd "$srcdir/demo/$_name"'
plan "$MONO" "$WORK/alpha.pkg.tar.zst"
check 'a cd this cannot resolve is refused' test "$?" -eq 2
check 'it names the line it will not read' says 'line 6 of demo/alpha/PKGBUILD'

reset_fixtures
write_carved 'cargo build --release'
plan "$MONO" "$WORK/alpha.pkg.tar.zst"
rc=$?
check 'a build that steps nowhere builds where the checkout is' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/out"
check 'and that is the builddir itself' says_line 'crate    /__w/demo/demo/alpha'

section 'case 4b — a package built from a tarball is the same rule'
reset_fixtures
write_candidate "$WORK/beta.pkg.tar.zst" beta 2.0-1 /__w/beta/beta glibc-2.44-1-x86_64
plan "$MONO" "$WORK/beta.pkg.tar.zst"
rc=$?
check 'the plan is made' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/out"
check 'meson reading $srcdir is not a cd' says_line 'crate    /__w/beta/beta'
check 'and nothing is laid out beside it' not says 'beside   '
check 'the tree is the packaging directory itself' test -f "$RUN/tree/beta/PKGBUILD"

# --- case 5: what has to sit beside it --------------------------------------

section 'case 5 — every crate reached by path is laid out around it'
reset_fixtures
plan "$MONO" "$WORK/alpha.pkg.tar.zst"
check 'a path dependency outside the package is a sibling' \
    says 'beside   packaging/alphalib at /__w/demo/demo/alpha/src/demo/alphalib'
check 'a dev-dependency is one too' \
    says 'beside   packaging/alphatest at /__w/demo/demo/alpha/src/demo/alphatest'
check 'a path dependency inside the package is not' not says 'beside   packaging/alpha/inner'

reset_fixtures
printf '[package]\nname = "alpha"\n\n[dependencies]\nout = { path = "../../../outside" }\n' \
    > "$MONO/packaging/alpha/Cargo.toml"
commit_monolith 'reach outside'
plan "$MONO" "$WORK/alpha.pkg.tar.zst"
check 'a path dependency that climbs out of the monolith is refused' test "$?" -eq 2
check 'it names the dependency' says 'the path dependency ../../../outside'

reset_fixtures
plan "$MONO" "$WORK/alpha.pkg.tar.zst"
check 'the tree comes from the commit and not the working tree' \
    test "$(cat "$RUN/tree/alpha/src/main.rs")" = committed
printf 'uncommitted\n' > "$MONO/packaging/alpha/src/main.rs"
plan "$MONO" "$WORK/alpha.pkg.tar.zst"
check 'an edit nobody committed is not in the reference' \
    test "$(cat "$RUN/tree/alpha/src/main.rs")" = committed

# --- case 6: the environment the candidate recorded -------------------------

section 'case 6 — the .BUILDINFO versions this machine would get wrong are pinned'
reset_fixtures
plan "$MONO" "$WORK/alpha.pkg.tar.zst"
check 'a package installed at another version is pinned' says 'pin      binutils-2.47-1-x86_64'
check 'one already at the right version is not' not says 'pin      glibc'
check 'one this build never installs is not' not says 'pin      pam'
check 'the pinned package is fetched' test -s "$RUN/pins/binutils-2.47-1-x86_64.pkg.tar.zst"

reset_fixtures
write_candidate "$WORK/gone.pkg.tar.zst" alpha 1.0-2 /__w/demo/demo/alpha \
    glibc-2.44-1-x86_64 binutils-2.46-3-x86_64
plan "$MONO" "$WORK/gone.pkg.tar.zst"
check 'a version nothing serves is refused' test "$?" -eq 2
check 'it names the package and the version' \
    says 'binutils-2.46-3-x86_64 is on no mirror and not on the archive'

# --- case 7: the pkgrel the candidate carries -------------------------------

section 'case 7 — the reference is built at the candidate pkgrel'
reset_fixtures
plan "$MONO" "$WORK/alpha.pkg.tar.zst"
check 'the plan says which release it builds' says 'package  alpha 1.0-2'
check 'and the staged PKGBUILD carries it' \
    grep -qx 'pkgrel=2' "$RUN/tree/alpha/PKGBUILD"

# --- case 8: comparing against the candidate --------------------------------

section 'case 8 — --compare needs the expectation file the package has'
reset_fixtures
plan --compare "$MONO" "$WORK/alpha.pkg.tar.zst"
check 'a package with no expectation file is refused' test "$?" -eq 2
check 'it names the file it looked for' says 'expected-diffs/alpha.txt'
check 'and the carved repository it fell back to' says 'expected-diffs/demo.txt'

# A repo carving several packages enumerates its tree once, under its own
# name, so a package with no file of its own is not a package with no
# expectations.
reset_fixtures
printf 'content usr/bin/alpha %064d..%064d — a difference someone read\n' 1 2 \
    > "$EXPECTED/demo.txt"
plan --compare "$MONO" "$WORK/alpha.pkg.tar.zst"
check "the carved repository's file stands in for a package with none" test "$?" -eq 0

# That file enumerates a carved tree once it pins git blobs, and
# compare-package.sh reads installed bytes: it would die inside its parser on
# the first pin, so the comparison is refused here by name.
reset_fixtures
printf 'content tree/usr/bin/alpha %040d..%040d — a difference someone read\n' 1 2 \
    > "$EXPECTED/demo.txt"
plan --compare "$MONO" "$WORK/alpha.pkg.tar.zst"
check 'a tree-form enumeration is refused rather than handed over' test "$?" -eq 2
check 'and it says what to do instead' says 'enumerates a carved tree'

reset_fixtures
plan --network bridge "$MONO" "$WORK/alpha.pkg.tar.zst"
rc=$?
check 'the container network can be named' test "$rc" -eq 0
[[ $rc -eq 0 ]] || cat "$WORK/out"

# --- case 9: the reference of a published package ---------------------------

section 'case 9 — a published package rebuilds to the sha its expectation pins'

PIN_PACKAGE=shedos-power
# Its expectations are the workspace's, and they enumerate a carved tree. The commit and
# the sha this case runs on are the artifact comparison that file keeps as history, which
# is the only place either is written down.
PIN_FILE=$ROOT/tools/expected-diffs/shedos-ui.txt
PIN_COMMIT=$(sed -n 's/.*at monolith commit \([0-9a-f]\{8\}\).*/\1/p' "$PIN_FILE" | head -1)
PIN_SHA=$(sed -n "s|^#[[:space:]]*content usr/bin/$PIN_PACKAGE \([0-9a-f]\{64\}\)\.\..*|\1|p" \
    "$PIN_FILE")
CANDIDATE_URL=https://repo.shedos.org/staging/test/x86_64

# Read out of the repository rather than out of the environment, so losing it
# is a failure and never a skip: it is the only acceptance proof there is.
check 'the expectation file still names the commit and the sha it was pinned against' \
    test -n "$PIN_COMMIT" -a -n "$PIN_SHA"

skip_reason=
[[ -n $PIN_COMMIT && -n $PIN_SHA ]] \
    || skip_reason="$PIN_FILE no longer names them"
[[ -n $skip_reason || -n ${SHEDOS_REFERENCE_MONOLITH:-} ]] \
    || skip_reason='SHEDOS_REFERENCE_MONOLITH does not name a monolith clone'
[[ -n $skip_reason ]] || command -v docker > /dev/null \
    || skip_reason='there is no docker on this machine'

if [[ -n $skip_reason ]]; then
    printf '  skip %s\n' "the end-to-end reference build — $skip_reason"
else
    version=$(git -C "$SHEDOS_REFERENCE_MONOLITH" show \
        "$PIN_COMMIT:packaging/$PIN_PACKAGE/PKGBUILD" \
        | sed -n 's/^pkgver=//p' | tr -d "\"'")
    candidate=$WORK/$PIN_PACKAGE.pkg.tar.zst
    file=$(curl -sSL -A 'shedos-release (+https://shedos.org)' \
        "$CANDIDATE_URL/shedos.db.tar.gz" | bsdtar -xOf - --include '*/desc' \
        | grep -xE "$PIN_PACKAGE-$version-[^-]+-x86_64\.pkg\.tar\.zst" | head -1)
    curl -fsSL -A 'shedos-release (+https://shedos.org)' -o "$candidate" \
        "$CANDIDATE_URL/$file"
    check 'the channel still serves the candidate the pin was written for' test -s "$candidate"

    reference=$(bash "$BUILD_REFERENCE" "$SHEDOS_REFERENCE_MONOLITH" "$candidate" \
        "$PIN_COMMIT" 2>&1 | tee "$WORK/e2e.log" | sed -n 's/^reference //p')
    check 'the reference builds' test -s "$reference"
    check 'its binary is the sha the expectation pins' \
        test "$(bsdtar -xOf "$reference" "usr/bin/$PIN_PACKAGE" | sha256sum | cut -d' ' -f1)" \
        = "$PIN_SHA"
    # The whole-package check needs an allowlist of installed bytes, which a tree-form
    # enumeration is not: it is rebuilt here from the evidence that file keeps.
    allowed=$WORK/$PIN_PACKAGE-allowed.txt
    sed -n "s|^#[[:space:]]*\(content usr/bin/$PIN_PACKAGE .*\)|\\1|p" "$PIN_FILE" > "$allowed"
    bash "$ROOT/tools/compare-package.sh" "$reference" "$candidate" "$allowed" \
        > "$WORK/e2e.compare" 2>&1
    check 'and the two packages are equivalent' test "$?" -eq 0
    [[ -s $WORK/e2e.compare ]] && sed 's/^/    /' "$WORK/e2e.compare"
fi

# --- result -----------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
