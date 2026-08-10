#!/usr/bin/env bash
# Equivalence harness. Real makepkg, real packages — every pair compared here
# is built on this machine from test/compare/fixtures, so the only differences
# are the ones the case put there. No root, no network.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
COMPARE=$ROOT/tools/compare-package.sh

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

cat > "$WORK/makepkg.conf" <<EOF
source /etc/makepkg.conf
PKGDEST='$WORK/pkgs'
SRCDEST='$WORK/src'
SRCPKGDEST='$WORK/srcpkg'
BUILDDIR='$WORK/build'
PKGEXT='.pkg.tar.zst'
BUILDENV=(!distcc color !check !sign)
OPTIONS=(!debug)
EOF
mkdir -p "$WORK/pkgs" "$WORK/src" "$WORK/srcpkg" "$WORK/build" "$WORK/fixture"
cp "$HERE/fixtures/gamma/PKGBUILD" "$WORK/fixture/PKGBUILD"

# Build gamma into $WORK/<name>.pkg.tar.zst. Everything after the name is an
# environment assignment, which is how a case says what it wants different.
# builddate and packager are always moved, so every comparison here is also
# proving that the two fields the tool ignores really are ignored.
epoch=1000000000
build() {
    local name=$1
    shift
    epoch=$((epoch + 86400))
    if ! (cd "$WORK/fixture" && env "$@" \
            SOURCE_DATE_EPOCH=$epoch \
            PACKAGER="packager $name <$name@shedos.invalid>" \
            makepkg --config "$WORK/makepkg.conf" --nodeps --force) \
            >>"$WORK/makepkg.log" 2>&1; then
        echo "could not build the $name fixture:" >&2
        tail -n 20 "$WORK/makepkg.log" >&2
        exit 1
    fi
    mv "$WORK/pkgs/gamma-1-1-any.pkg.tar.zst" "$WORK/$name.pkg.tar.zst"
}

build reference
build same
build changed   GAMMA_DATA=altered
build extra     GAMMA_EXTRA=bonus.txt
build depended  GAMMA_DEPENDS=bash
build relinked  GAMMA_LINK=steady.txt
build shaped    GAMMA_SHAPE=link
build twinned   GAMMA_TWIN=hard
build setuid    GAMMA_MODE=4755

# --- helpers ----------------------------------------------------------------

# One expected-diffs file per case, so no case can be rescued by another's.
diffs() {
    local name=$1 content=$2
    printf '%s' "$content" > "$WORK/$name.diffs"
    printf '%s' "$WORK/$name.diffs"
}

# Compare two builds. Output lands in $WORK/<name>.out. With no expected-diffs
# file of its own a case gets an empty one, so the default is an allowlist
# that permits nothing.
compare_pair() {
    local name=$1 reference=$2 candidate=$3
    local expected=${4:-}
    [[ -n $expected ]] || expected=$(diffs "$name-empty" '')
    bash "$COMPARE" "$WORK/$reference.pkg.tar.zst" "$WORK/$candidate.pkg.tar.zst" \
        "$expected" > "$WORK/$name.out" 2>&1
}

# The common shape: <candidate> against the reference build.
compare() { compare_pair "$1" reference "$2" "${3:-}"; }

# The sha256 of one path inside one build, which is what an expectation pins.
sha_in() {
    bsdtar -xOf "$WORK/$1.pkg.tar.zst" "$2" | sha256sum | cut -d' ' -f1
}

# The lines that are findings, as opposed to the matched expectations, the
# notes and the summary.
findings() {
    grep -E '^(pkginfo |manifest only-in-|content: |mtree |stale expectation: )' \
        "$WORK/$1.out"
}

finding_count() { findings "$1" | wc -l; }

says() { grep -qF "$2" "$WORK/$1.out"; }

# --- case 1: equivalent -----------------------------------------------------

section 'case 1 — two builds of the same fixture are equivalent'
compare same same
check 'compare succeeds' test "$?" -eq 0
check 'nothing is reported' test "$(finding_count same)" -eq 0
check 'it says so' says same 'equivalent'
[[ $(finding_count same) -eq 0 ]] || cat "$WORK/same.out"

section 'case 1b — the ignored fields really were ignored'
check 'builddate differs between the two builds' \
    not cmp -s <(bsdtar -xOf "$WORK/reference.pkg.tar.zst" .PKGINFO | grep builddate) \
               <(bsdtar -xOf "$WORK/same.pkg.tar.zst" .PKGINFO | grep builddate)
check 'packager differs between the two builds' \
    not cmp -s <(bsdtar -xOf "$WORK/reference.pkg.tar.zst" .PKGINFO | grep packager) \
               <(bsdtar -xOf "$WORK/same.pkg.tar.zst" .PKGINFO | grep packager)

# --- case 2: a content difference -------------------------------------------

section 'case 2 — a file whose content differs is reported'
compare changed changed
check 'compare fails' test "$?" -ne 0
check 'the data file is reported' \
    test "$(findings changed)" = 'content: usr/share/gamma/data.txt'
check 'and nothing else is' test "$(finding_count changed)" -eq 1
check 'the summary says it is not equivalent' says changed 'NOT equivalent'

# --- case 3: the same difference, allowed -----------------------------------

section 'case 3 — an expected difference is allowed'
compare allowed changed \
    "$(diffs allowed $'# the harness changed this on purpose\ncontent usr/share/gamma/data.txt — harness rewrote it\n')"
check 'compare succeeds' test "$?" -eq 0
check 'nothing is reported' test "$(finding_count allowed)" -eq 0
check 'the matched expectation is printed with its reason' \
    says allowed 'expected: usr/share/gamma/data.txt (harness rewrote it)'
[[ $(finding_count allowed) -eq 0 ]] || cat "$WORK/allowed.out"

# --- case 4: an expectation that matched nothing ----------------------------

section 'case 4 — an expectation that matches nothing is itself a failure'
compare stale same \
    "$(diffs stale $'content usr/share/gamma/data.txt — nothing differs here any more\n')"
check 'compare fails' test "$?" -ne 0
check 'the stale entry is named' \
    test "$(findings stale)" = 'stale expectation: usr/share/gamma/data.txt'

# A stale entry has to be caught even when the run has real findings to
# report, or a drifting allowlist would hide behind them.
compare stale-too changed \
    "$(diffs stale-too $'content usr/share/gamma/data.txt — harness rewrote it\ncontent usr/share/gamma/steady.txt — nothing differs here\n')"
check 'compare fails when a stale entry rides along with a real one' \
    test "$?" -ne 0
check 'the stale entry is still named' \
    says stale-too 'stale expectation: usr/share/gamma/steady.txt'
check 'and the one that matched is still credited' \
    says stale-too 'expected: usr/share/gamma/data.txt'

# --- case 5: a manifest difference ------------------------------------------

section 'case 5 — an extra file in the candidate is reported'
compare added extra
check 'compare fails' test "$?" -ne 0
check 'the extra path is reported' \
    says added 'manifest only-in-cand: usr/share/gamma/bonus.txt'

section 'case 5b — a manifest difference cannot be allowlisted'
compare added-allowed extra \
    "$(diffs added-allowed $'content usr/share/gamma/bonus.txt — try to wave it through\n')"
check 'compare still fails' test "$?" -ne 0
check 'the extra path is still reported' \
    says added-allowed 'manifest only-in-cand: usr/share/gamma/bonus.txt'
check 'and the entry that tried to wave it through is stale' \
    says added-allowed 'stale expectation: usr/share/gamma/bonus.txt'

section 'case 5c — the allowlist only takes content entries'
compare added-bogus extra \
    "$(diffs added-bogus $'manifest only-in-cand usr/share/gamma/bonus.txt — not a thing\n')"
check 'compare fails' test "$?" -ne 0
check 'it refuses the directive by name' says added-bogus "only 'content'"

# --- case 6: a metadata difference ------------------------------------------

section 'case 6 — a changed dependency is reported'
compare dep depended
check 'compare fails' test "$?" -ne 0
check 'the field is reported' says dep 'pkginfo depend:'
check 'with both sides' says dep 'bash'

section 'case 6b — a metadata difference cannot be allowlisted'
compare dep-allowed depended \
    "$(diffs dep-allowed $'content .PKGINFO — try to wave it through\n')"
check 'compare still fails' test "$?" -ne 0
check 'the field is still reported' says dep-allowed 'pkginfo depend:'

# --- case 7: a symlink that points somewhere else ---------------------------
#
# Extracting a symlink yields no bytes, so hashing alone calls two symlinks
# with different targets identical.

section 'case 7 — a symlink retargeted in the candidate is reported'
compare link relinked
check 'compare fails' test "$?" -ne 0
check 'the symlink is reported' \
    test "$(findings link)" = 'content: usr/share/gamma/current'

# --- case 8: a directory that becomes a symlink -----------------------------
#
# An empty directory and a symlink land on the same manifest entry once the
# trailing slash is normalised away, so nothing above the content tier can
# see this. Deciding what to skip by the reference side alone used to let it
# through as equivalent.

section 'case 8 — an empty directory that becomes a symlink is reported'
check 'the two builds really do have identical manifests' \
    cmp -s <(bsdtar -tf "$WORK/reference.pkg.tar.zst" | sed -e 's|/$||' | sort) \
           <(bsdtar -tf "$WORK/shaped.pkg.tar.zst" | sed -e 's|/$||' | sort)
compare shape shaped
check 'compare fails' test "$?" -ne 0
# Two detectors fire here and they are not redundant. The mtree tier sees the
# type change on its own, so a run would still fail without the content tier
# ever looking — which is how this got through the first time. The content
# line is the one under test, so it is asserted by name rather than through
# the exit status, and the mtree line is checked separately to keep anyone
# from later deciding the two are the same assertion.
check 'the content tier reports it' says shape 'content: usr/share/gamma/spot'
check 'and the mtree tier corroborates independently' \
    says shape 'mtree usr/share/gamma/spot: type dir != link'

section 'case 8b — and so is a symlink that becomes an empty directory'
compare_pair shape-back shaped reference
check 'compare fails' test "$?" -ne 0
check 'the content tier reports it' says shape-back 'content: usr/share/gamma/spot'
check 'and the mtree tier corroborates independently' \
    says shape-back 'mtree usr/share/gamma/spot: type link != dir'

# --- case 9: size that the content tier cannot explain ----------------------
#
# makepkg counts a hardlinked file once, so replacing a hardlink with a copy
# moves the installed size while the manifest and every hash stay put.

section 'case 9 — a size the content findings do not explain is reported'
check 'the two builds really do have identical manifests' \
    cmp -s <(bsdtar -tf "$WORK/reference.pkg.tar.zst" | sort) \
           <(bsdtar -tf "$WORK/twinned.pkg.tar.zst" | sort)
compare twin twinned
check 'compare fails' test "$?" -ne 0
check 'no content difference was found at all' \
    not grep -q '^content: ' "$WORK/twin.out"
check 'the size is reported against what content predicted' \
    grep -q '^pkginfo size: observed .* != predicted 0 from the content findings' \
        "$WORK/twin.out"

section 'case 9b — that size finding cannot be allowlisted'
compare twin-allowed twinned \
    "$(diffs twin-allowed $'content usr/share/gamma/pair-b.txt — try to wave it through\n')"
check 'compare still fails' test "$?" -ne 0
check 'the size is still reported' says twin-allowed 'pkginfo size: observed'

section 'case 9c — a size that the content findings do explain is only a note'
compare size-note changed \
    "$(diffs size-note $'content usr/share/gamma/data.txt — harness rewrote it\n')"
check 'compare succeeds' test "$?" -eq 0
check 'nothing is reported' test "$(finding_count size-note)" -eq 0
check 'the size move is noted rather than gated' \
    grep -q '^note: size .* accounted for by the content findings' \
        "$WORK/size-note.out"

# --- case 10: expectations pinned to one exact difference -------------------

section 'case 10 — a pinned expectation matches only that difference'
pin=$(sha_in reference usr/share/gamma/data.txt)..$(sha_in changed usr/share/gamma/data.txt)
compare pinned changed \
    "$(diffs pinned "content usr/share/gamma/data.txt $pin — harness rewrote it")"
check 'compare succeeds' test "$?" -eq 0
check 'nothing is reported' test "$(finding_count pinned)" -eq 0
check 'the expectation is credited' \
    says pinned 'expected: usr/share/gamma/data.txt (harness rewrote it)'
check 'a pinned entry is not called unpinned' \
    not grep -q 'unpinned expectation' "$WORK/pinned.out"
[[ $(finding_count pinned) -eq 0 ]] || cat "$WORK/pinned.out"

section 'case 10b — a pin stops matching once the difference changes'
# The same path differing in a different way: the pin was written for the
# reference-to-changed pair, and this run compares reference to relinked.
compare pin-moved relinked \
    "$(diffs pin-moved "content usr/share/gamma/current $pin — pinned to the wrong pair")"
check 'compare fails' test "$?" -ne 0
check 'the difference is unexplained' says pin-moved 'content: usr/share/gamma/current'
check 'and the pin that no longer describes it is stale' \
    says pin-moved 'stale expectation: usr/share/gamma/current'

section 'case 10c — an unpinned expectation says that it is unpinned'
compare unpinned changed \
    "$(diffs unpinned $'content usr/share/gamma/data.txt — harness rewrote it\n')"
check 'compare succeeds' test "$?" -eq 0
check 'the entry is credited' says unpinned 'expected: usr/share/gamma/data.txt'
check 'and flagged as unpinned' \
    says unpinned 'note: unpinned expectation usr/share/gamma/data.txt'

section 'case 10d — an entry with no reason is refused'
compare reasonless changed \
    "$(diffs reasonless $'content usr/share/gamma/data.txt\n')"
check 'compare fails' test "$?" -ne 0
check 'it says what the format is' says reasonless '<reason>'

# --- case 11: mode, owner and type ------------------------------------------
#
# .MTREE is the only trustworthy record of these: the tool extracts
# unprivileged, so a setuid bit would not survive into the extracted tree.

section 'case 11 — a setuid bit set in the candidate is reported'
check 'the bytes are identical on both sides' \
    test "$(sha_in reference usr/share/gamma/steady.txt)" \
       = "$(sha_in setuid usr/share/gamma/steady.txt)"
compare mode setuid
check 'compare fails' test "$?" -ne 0
check 'the mode change is reported' \
    test "$(findings mode)" = 'mtree usr/share/gamma/steady.txt: mode 644 != 4755'

section 'case 11b — a mode difference cannot be allowlisted'
compare mode-allowed setuid \
    "$(diffs mode-allowed $'content usr/share/gamma/steady.txt — try to wave it through\n')"
check 'compare still fails' test "$?" -ne 0
check 'the mode change is still reported' says mode-allowed 'mtree usr/share/gamma/steady.txt: mode'

# --- usage ------------------------------------------------------------------

section 'usage'
check 'a missing reference is refused' \
    not bash "$COMPARE" "$WORK/nope.pkg.tar.zst" "$WORK/same.pkg.tar.zst" \
        "$(diffs usage '')"
check 'a missing expected-diffs file is refused' \
    not bash "$COMPARE" "$WORK/reference.pkg.tar.zst" "$WORK/same.pkg.tar.zst" \
        "$WORK/nope.diffs"
check 'the wrong number of arguments is refused' \
    not bash "$COMPARE" "$WORK/reference.pkg.tar.zst"

# --- summary ----------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
