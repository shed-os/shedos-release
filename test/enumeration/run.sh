#!/usr/bin/env bash
# Enumeration harness. Real git repositories built here — a fixture monolith
# and the repositories a carve of it would produce, each shaped to one thing
# the instrument has to get right. No root, no network.
#
# The three cases at the end are the ones that cannot be faked: they re-derive
# figures the wave published, against the real monolith and the real carved
# repositories at the commits those figures were measured at. They need clones
# and say which one is missing when they skip.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
VERIFY=$ROOT/tools/verify-enumeration.sh

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

# --- fixtures ---------------------------------------------------------------

new_repo() {
    git init -q -b main "$1"
    git -C "$1" config user.email harness@shedos.invalid
    git -C "$1" config user.name 'enumeration harness'
}

commit_all() { git -C "$1" add -A && git -C "$1" commit -q -m "$2"; }

write() { mkdir -p "$(dirname "$1")" && printf '%s\n' "$2" > "$1"; }

# The fixture monolith: one package with a payload tree, man sources and two
# out-of-tree suites, plus a directory that belongs to nobody.
MONO=$WORK/mono
new_repo "$MONO"
write "$MONO/packaging/alpha/PKGBUILD"                 'pkgname=alpha'
write "$MONO/packaging/alpha/tree/usr/bin/alpha"       'the dispatcher'
write "$MONO/packaging/alpha/tree/usr/libexec/alpha/one" 'the first verb'
write "$MONO/packaging/alpha/tree/usr/libexec/alpha/two" 'the second verb'
write "$MONO/packaging/alpha/tree/etc/alpha.conf"      'a setting'
write "$MONO/packaging/alpha/man/alpha.1.scd"          'ALPHA(1)'
write "$MONO/packaging/alpha/man/alpha-two.1.scd"      'ALPHA-TWO(1)'
write "$MONO/test/alpha/run.sh"                        'the alpha suite'
write "$MONO/test/alpha/fixtures/case"                 'a fixture'
write "$MONO/test/two/run.sh"                          'the two suite'
write "$MONO/unrelated/junk"                           'not anybody here'
commit_all "$MONO" 'the monolith as the carve found it'
MONO_AT=$(git -C "$MONO" rev-parse HEAD)

maps() { printf '%s' "$2" > "$WORK/$1.paths"; printf '%s' "$WORK/$1.paths"; }

ALPHA_MAP=$(maps alpha "$(cat <<'EOF'
flatten packaging/alpha
except packaging/alpha/tree/usr/libexec/alpha/two
except packaging/alpha/man/alpha-two.1.scd
path test/alpha/
EOF
)")

TWO_MAP=$(maps two "$(cat <<'EOF'
new-package two
rename packaging/alpha/tree/usr/libexec/alpha/two:tree/usr/libexec/alpha/two
rename packaging/alpha/man/alpha-two.1.scd:man/alpha-two.1.scd
path test/two/
EOF
)")

# What the carve of alpha produces: the package flattened to the root, minus
# the two files the split gave away, with its suite where it sat.
carve_alpha() {
    local repo=$1
    new_repo "$repo"
    mkdir -p "$repo/tree/usr/bin" "$repo/tree/usr/libexec/alpha" "$repo/tree/etc" \
        "$repo/man" "$repo/test/alpha/fixtures"
    cp "$MONO/packaging/alpha/PKGBUILD"                   "$repo/PKGBUILD"
    cp "$MONO/packaging/alpha/tree/usr/bin/alpha"         "$repo/tree/usr/bin/alpha"
    cp "$MONO/packaging/alpha/tree/usr/libexec/alpha/one" "$repo/tree/usr/libexec/alpha/one"
    cp "$MONO/packaging/alpha/tree/etc/alpha.conf"        "$repo/tree/etc/alpha.conf"
    cp "$MONO/packaging/alpha/man/alpha.1.scd"            "$repo/man/alpha.1.scd"
    cp "$MONO/test/alpha/run.sh"                          "$repo/test/alpha/run.sh"
    cp "$MONO/test/alpha/fixtures/case"                   "$repo/test/alpha/fixtures/case"
    commit_all "$repo" 'carve alpha out of the monolith'
}

ROOT_REPO=$WORK/alpha-root
carve_alpha "$ROOT_REPO"

# The same repository once the task that carved it has done its work: one file
# rewritten, one file the monolith never had, one mode moved.
CLOSE_REPO=$WORK/alpha-close
carve_alpha "$CLOSE_REPO"
write "$CLOSE_REPO/tree/usr/bin/alpha" 'the dispatcher, reading its config'
write "$CLOSE_REPO/tree/usr/share/alpha/verbs.d/one.toml" 'name = "one"'
chmod 755 "$CLOSE_REPO/tree/usr/libexec/alpha/one"
commit_all "$CLOSE_REPO" 'what the split changed'

# The new-name half of the split.
TWO_REPO=$WORK/two
new_repo "$TWO_REPO"
mkdir -p "$TWO_REPO/tree/usr/libexec/alpha" "$TWO_REPO/man" "$TWO_REPO/test/two"
cp "$MONO/packaging/alpha/tree/usr/libexec/alpha/two" "$TWO_REPO/tree/usr/libexec/alpha/two"
cp "$MONO/packaging/alpha/man/alpha-two.1.scd"        "$TWO_REPO/man/alpha-two.1.scd"
cp "$MONO/test/two/run.sh"                            "$TWO_REPO/test/two/run.sh"
write "$TWO_REPO/PKGBUILD" 'pkgname=two'
commit_all "$TWO_REPO" 'carve two out of alpha'

blob() { git -C "$1" rev-parse "HEAD:$2"; }

run() { bash "$VERIFY" "$@" > "$WORK/out" 2>&1; }
said() { grep -qF "$1" "$WORK/out"; }
not() { ! "$@"; }
quiet() { "$@" > /dev/null 2>&1; }

# --- the walk ---------------------------------------------------------------

section 'a carve root is identical to the monolith it came from'

run repo "$ALPHA_MAP" "$MONO" "$MONO_AT" "$ROOT_REPO" HEAD
check 'the walk succeeds' [ $? -eq 0 ]
check 'nothing differs and nothing is unaccounted for' \
    said 'package 5/0, test 2/0, no counterpart 0'
check 'and it says so' said 'reconciled — nothing unaccounted for'
[[ $fail -eq 0 ]] || cat "$WORK/out"

section 'a carved repository that has moved on'

run repo "$ALPHA_MAP" "$MONO" "$MONO_AT" "$CLOSE_REPO" HEAD
check 'the transformed file and the new one are counted apart' \
    said 'package 4/1, test 2/0, no counterpart 1'
check 'the mode change is a finding of its own' \
    said 'mode tree/usr/libexec/alpha/one 100644 -> 100755'

section 'the half of the split that has no monolith package'

run repo "$TWO_MAP" "$MONO" "$MONO_AT" "$TWO_REPO" HEAD
check 'the renamed files are matched through the rename' \
    said 'package 2/0, test 1/0, no counterpart 1'

# --- reconciling against the enumeration ------------------------------------

section 'the enumeration is held to the tree in both directions'

DASH=$'—'
expectation() { printf 'content %s %s..%s %s %s\n' "$2" "$3" "$4" "$DASH" "$5" >> "$1"; }

GOOD=$WORK/good.txt
: > "$GOOD"
expectation "$GOOD" tree/usr/bin/alpha \
    "$(blob "$MONO" packaging/alpha/tree/usr/bin/alpha)" \
    "$(blob "$CLOSE_REPO" tree/usr/bin/alpha)" 'it reads its config now'

run repo "$ALPHA_MAP" "$MONO" "$MONO_AT" "$CLOSE_REPO" HEAD "$GOOD"
check 'a file that differs and is written down reconciles' \
    said 'claimed 1, transformed 1, reconciled 1'
check 'the mode finding still stands on its own' said 'NOT reconciled'

EMPTY=$WORK/empty.txt
printf '# a repository that has changed nothing yet\n' > "$EMPTY"
run repo "$ALPHA_MAP" "$MONO" "$MONO_AT" "$ROOT_REPO" HEAD "$EMPTY"
check 'a repository with nothing to reconcile reconciles' \
    said 'claimed 0, transformed 0, reconciled 0'
check 'and it passes' said 'reconciled — nothing unaccounted for'

SILENT=$WORK/silent.txt
: > "$SILENT"
run repo "$ALPHA_MAP" "$MONO" "$MONO_AT" "$CLOSE_REPO" HEAD "$SILENT"
check 'a difference nobody wrote down is named' \
    said 'transformed and not written down: tree/usr/bin/alpha'

STALE=$WORK/stale.txt
cp "$GOOD" "$STALE"
expectation "$STALE" tree/etc/alpha.conf \
    "$(blob "$MONO" packaging/alpha/tree/etc/alpha.conf)" \
    "$(blob "$CLOSE_REPO" tree/etc/alpha.conf)" 'a setting that never moved'
run repo "$ALPHA_MAP" "$MONO" "$MONO_AT" "$CLOSE_REPO" HEAD "$STALE"
check 'an expectation describing nothing is named' \
    said 'written down and not a difference: tree/etc/alpha.conf'

MOVED=$WORK/moved.txt
printf 'content tree/usr/bin/alpha %040d..%040d %s a pin written for other bytes\n' \
    1 2 "$DASH" > "$MOVED"
run repo "$ALPHA_MAP" "$MONO" "$MONO_AT" "$CLOSE_REPO" HEAD "$MOVED"
check 'a pin that no longer names the two blobs stops matching' \
    said 'written down and not a difference: tree/usr/bin/alpha'
check 'and the difference it was written for is loose again' \
    said 'transformed and not written down: tree/usr/bin/alpha'

LOOSE=$WORK/loose.txt
printf 'content tree/usr/bin/alpha %s it reads its config now\n' "$DASH" > "$LOOSE"
run repo "$ALPHA_MAP" "$MONO" "$MONO_AT" "$CLOSE_REPO" HEAD "$LOOSE"
check 'an unpinned expectation is credited and called out' \
    said 'note: unpinned expectation tree/usr/bin/alpha'

PACKAGED=$WORK/packaged.txt
printf 'content usr/bin/alpha %064d..%064d %s the shape a built package takes\n' \
    1 2 "$DASH" > "$PACKAGED"
run repo "$ALPHA_MAP" "$MONO" "$MONO_AT" "$CLOSE_REPO" HEAD "$PACKAGED"
check 'an enumeration of a built package is refused rather than reconciled' \
    said "pins a built package's bytes"

# The shape every Wave 1-2 expectation file was converted into: prose keeping what
# the artifact comparison of the two packages found, sha256 pins and all, over
# tree-form entries that govern the source. The pins are history in a comment and no
# expectation is made of them — a refusal that read the whole file rather than its
# directives would take every converted file with it.
CONVERTED=$WORK/converted.txt
{
    printf '# --- the artifact comparison, kept as history ---\n'
    printf '#   content usr/bin/alpha %064d..%064d %s the pair it was pinned to\n' \
        1 2 "$DASH"
} > "$CONVERTED"
expectation "$CONVERTED" tree/usr/bin/alpha \
    "$(blob "$MONO" packaging/alpha/tree/usr/bin/alpha)" \
    "$(blob "$CLOSE_REPO" tree/usr/bin/alpha)" 'it reads its config now'

run repo "$ALPHA_MAP" "$MONO" "$MONO_AT" "$CLOSE_REPO" HEAD "$CONVERTED"
check 'a converted file reconciles on its tree entries' \
    said 'claimed 1, transformed 1, reconciled 1'
check 'and the sha256 pins it keeps as history are not read as expectations' \
    not said "pins a built package's bytes"

# --- what a walk of one repository can still see -----------------------------

section 'the map and the tree are held against each other'

GONE=$WORK/alpha-gone
carve_alpha "$GONE"
git -C "$GONE" rm -q "man/alpha.1.scd"
commit_all "$GONE" 'drop the page'
run repo "$ALPHA_MAP" "$MONO" "$MONO_AT" "$GONE" HEAD
check 'a file the map selects and the tree does not hold is named' \
    said 'selected and absent from the tree: man/alpha.1.scd'

KEPT=$WORK/alpha-kept
carve_alpha "$KEPT"
cp "$MONO/packaging/alpha/man/alpha-two.1.scd" "$KEPT/man/alpha-two.1.scd"
commit_all "$KEPT" 'keep the page the split gave away'
run repo "$ALPHA_MAP" "$MONO" "$MONO_AT" "$KEPT" HEAD
check 'a file the map excepts and the tree still holds is named' \
    said 'excepted and present in the tree: man/alpha-two.1.scd'

HISTORIC=$(maps historic "$(cat <<'EOF'
flatten packaging/alpha
except packaging/alpha/tree/usr/libexec/alpha/two
except packaging/alpha/man/alpha-two.1.scd
except packaging/alpha/tree/etc/old-alpha.conf
path test/alpha/
EOF
)")
run repo "$HISTORIC" "$MONO" "$MONO_AT" "$ROOT_REPO" HEAD
check 'an except only the history has is noted and not refused' \
    said 'excepts packaging/alpha/tree/etc/old-alpha.conf, which the tree at this commit does not have'
check 'and the walk still passes' said 'reconciled — nothing unaccounted for'

# --- the split, held together ------------------------------------------------

section 'the whole split against the directory it came out of'

MAPS_DIR=$WORK/maps
mkdir -p "$MAPS_DIR"
cp "$ALPHA_MAP" "$MAPS_DIR/alpha.paths"
cp "$TWO_MAP" "$MAPS_DIR/two.paths"

run set "$MAPS_DIR" "$MONO" "$MONO_AT" packaging/alpha \
    alpha="$CLOSE_REPO" two="$TWO_REPO"
check 'every file under the origin is claimed exactly once' \
    said 'claimed once 7, claimed by none 0, claimed by several 0, claimed and absent 0'
check 'and the split reconciles' said 'reconciled — nothing unaccounted for'
[[ $fail -eq 0 ]] || cat "$WORK/out"

# The whole point: a file that leaves a package and is claimed by nobody is a
# file the split deleted in silence, and a walk of either side alone sees a
# tree that is exactly what its own map asked for.
DROPPED=$WORK/dropped
mkdir -p "$DROPPED"
cp "$ALPHA_MAP" "$DROPPED/alpha.paths"
grep -v 'alpha-two.1.scd' "$TWO_MAP" > "$DROPPED/two.paths"
DROP_REPO=$WORK/two-dropped
new_repo "$DROP_REPO"
mkdir -p "$DROP_REPO/tree/usr/libexec/alpha" "$DROP_REPO/test/two"
cp "$MONO/packaging/alpha/tree/usr/libexec/alpha/two" "$DROP_REPO/tree/usr/libexec/alpha/two"
cp "$MONO/test/two/run.sh" "$DROP_REPO/test/two/run.sh"
commit_all "$DROP_REPO" 'carve two without the page'

run set "$DROPPED" "$MONO" "$MONO_AT" packaging/alpha \
    alpha="$ROOT_REPO" two="$DROP_REPO"
check 'a file no map claims reddens the split' said 'claimed by none 1'
check 'and it is named' said 'no map claims packaging/alpha/man/alpha-two.1.scd'
check 'while a walk of one side passes' \
    quiet bash "$VERIFY" repo "$ALPHA_MAP" "$MONO" "$MONO_AT" "$ROOT_REPO" HEAD
check 'and so does a walk of the other' \
    quiet bash "$VERIFY" repo "$DROPPED/two.paths" "$MONO" "$MONO_AT" "$DROP_REPO" HEAD

TWICE=$WORK/twice
mkdir -p "$TWICE"
grep -v 'except packaging/alpha/man/alpha-two.1.scd' "$ALPHA_MAP" > "$TWICE/alpha.paths"
cp "$TWO_MAP" "$TWICE/two.paths"
run set "$TWICE" "$MONO" "$MONO_AT" packaging/alpha alpha="$KEPT" two="$TWO_REPO"
check 'a file two maps claim is named with both of them' \
    said 'packaging/alpha/man/alpha-two.1.scd is claimed by alpha two'

run set "$MAPS_DIR" "$MONO" "$MONO_AT" packaging/alpha alpha="$CLOSE_REPO"
check 'a member left off the command line is refused by name' \
    said 'no repository was given for them: two'

run set "$MAPS_DIR" "$MONO" "$MONO_AT" packaging/alpha \
    alpha="$CLOSE_REPO" two="$DROP_REPO"
check 'a file that left and never arrived is named with where it went' \
    said 'packaging/alpha/man/alpha-two.1.scd went to two and two does not hold man/alpha-two.1.scd'

# --- the figures the wave published -----------------------------------------

section 'the figures Wave 3 measured, re-derived'

skip_reason=
[[ -n ${SHEDOS_ENUMERATION_MONOLITH:-} ]] \
    || skip_reason='SHEDOS_ENUMERATION_MONOLITH does not name a monolith clone'
[[ -n $skip_reason || -n ${SHEDOS_ENUMERATION_SHEDMAN:-} ]] \
    || skip_reason='SHEDOS_ENUMERATION_SHEDMAN does not name a shedman clone'
[[ -n $skip_reason || -n ${SHEDOS_ENUMERATION_SHEDOS_SYSTEM:-} ]] \
    || skip_reason='SHEDOS_ENUMERATION_SHEDOS_SYSTEM does not name a shedos-system clone'

if [[ -n $skip_reason ]]; then
    printf '  skip %s\n' "the published figures — $skip_reason"
else
    # The commits are the ones the figures were measured at, and the maps are
    # today's: a map that has grown since selects paths the older tree has not
    # got yet, which the run says out loud and which moves no count.
    figure() {
        local desc=$1 map=$2 repo=$3 ref=$4 want=$5
        bash "$VERIFY" repo "$ROOT/tools/carve-maps/$map.paths" \
            "$SHEDOS_ENUMERATION_MONOLITH" 2c377ee7 "$repo" "$ref" > "$WORK/out" 2>&1
        check "$desc" said "$want"
    }
    figure 'the shedos-system carve root is the monolith exactly' \
        shedos-system "$SHEDOS_ENUMERATION_SHEDOS_SYSTEM" bc6d980 \
        'package 158/0, test 27/0, no counterpart 0'
    figure 'shedos-system at the close of its task' \
        shedos-system "$SHEDOS_ENUMERATION_SHEDOS_SYSTEM" af94b7d \
        'package 154/4, test 0/27, no counterpart 15'
    figure 'shedman at the close of its task' \
        shedman "$SHEDOS_ENUMERATION_SHEDMAN" d3e9d74 \
        'package 37/5, test 479/12, no counterpart 24'
fi

# --- result -----------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
