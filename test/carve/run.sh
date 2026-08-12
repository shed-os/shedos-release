#!/usr/bin/env bash
# Carve harness. Real git, real filter-repo, real pushes — the monolith is a
# fixture repo built here and every remote is a bare repo in the temp dir.
# Nothing reaches GitHub.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
CARVE=$ROOT/tools/carve.sh

if ! git filter-repo --version >/dev/null 2>&1; then
    echo "git-filter-repo is not installed; carve.sh cannot be exercised" >&2
    echo "install it with: pacman -S git-filter-repo" >&2
    exit 1
fi

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

# --- fixture monolith -------------------------------------------------------
#
# Small, but it carries every shape the carve has to get right: a package
# directory to flatten, a second tree that belongs to the same package, a file
# that moved between directories, a sibling whose name starts with the same
# letters as that move's source, release tags, and something that must never
# come along.

MONO=$WORK/mono
git init -q -b main "$MONO"
git -C "$MONO" config user.email harness@shedos.invalid
git -C "$MONO" config user.name 'carve harness'

mono_commit() { git -C "$MONO" add -A && git -C "$MONO" commit -q -m "$1"; }

mkdir -p "$MONO"/{packaging/cage,unrelated,old,oldies}
echo pkgbuild > "$MONO/packaging/cage/PKGBUILD"
echo junk > "$MONO/unrelated/junk"
mono_commit 'add cage and something unrelated'

echo v1 > "$MONO/old/lib.sh"
echo sibling > "$MONO/oldies/note"
mono_commit 'add lib while it still lives in old'

echo v2 >> "$MONO/old/lib.sh"
mono_commit 'edit lib in place'

git -C "$MONO" tag -a v2026.01.01 -m 'a monolith release'

mkdir -p "$MONO/new"
git -C "$MONO" mv old/lib.sh new/lib.sh
mono_commit 'move lib from old to new'

echo v3 >> "$MONO/new/lib.sh"
mono_commit 'edit lib after the move'

mkdir -p "$MONO/test/cage"
echo patch > "$MONO/packaging/cage/0001.patch"
echo suite > "$MONO/test/cage/run.sh"
echo more >> "$MONO/unrelated/junk"
mono_commit 'add the cage patch and its out-of-tree suite'

git -C "$MONO" tag -a v2026.02.02 -m 'another monolith release'

# The monolith is a clone of something, the way the real one is, so a carve can
# ask whether it is still level with it.
MONO_ORIGIN=$WORK/mono-origin.git
git init -q --bare -b main "$MONO_ORIGIN"
git -C "$MONO" remote add origin "$MONO_ORIGIN"
git -C "$MONO" push -q origin main

# --- helpers ----------------------------------------------------------------

maps() { printf '%s' "$2" > "$WORK/$1.paths"; printf '%s' "$WORK/$1.paths"; }

bare_of() { printf '%s' "$WORK/remotes/$1.git"; }

# Carve into a bare repo of its own. Output lands in $WORK/<target>.out.
carve() {
    local target=$1 mapfile=$2 mono=${3:-$MONO}
    local bare
    bare=$(bare_of "$target")
    rm -rf "$bare"
    git init -q --bare "$bare"
    SHEDOS_CARVE_REMOTE=$bare bash "$CARVE" "$mono" "$target" "$mapfile" \
        > "$WORK/$target.out" 2>&1
}

pushed_paths() {
    git -C "$(bare_of "$1")" log --format= --name-only main 2>/dev/null \
        | sed '/^$/d' | LC_ALL=C sort -u | tr '\n' ' '
}
pushed_commits() { git -C "$(bare_of "$1")" rev-list --count main 2>/dev/null; }
pushed_tags()    { git -C "$(bare_of "$1")" tag -l | wc -l; }
pushed_refs()    { git -C "$(bare_of "$1")" for-each-ref --format='%(refname)' | wc -l; }
subjects()       { git -C "$(bare_of "$1")" log --format='%s' main 2>/dev/null; }

# A maps file that must be refused: refused for the stated reason, and before
# anything is pushed. Matching the reason keeps a case from passing because
# the carve fell over somewhere else entirely.
refuses() {
    local desc=$1 target=$2 content=$3 want=$4 mono=${5:-$MONO}
    if carve "$target" "$(maps "$target" "$content")" "$mono"; then
        bad "$desc — the carve succeeded"
        return
    fi
    if (( $(pushed_refs "$target") != 0 )); then
        bad "$desc — died but had already pushed"
        return
    fi
    if ! grep -qF "$want" "$WORK/$target.out"; then
        bad "$desc — died on something else: $(tail -1 "$WORK/$target.out")"
        return
    fi
    ok "$desc"
}

# --- maps files that must never carve ---------------------------------------

section 'maps validation'

refuses 'unknown directive'          bad-directive $'bogus packaging/cage\n' \
        "unknown directive 'bogus' on line 1"
refuses 'path with no value'         bad-path      $'path\n' \
        'path on line 1 of'
refuses 'path with only whitespace'  bad-path-ws   $'path   \n' \
        'path on line 1 of'
refuses 'flatten with no value'      bad-flatten   $'flatten\n' \
        'flatten on line 1 of'
refuses 'rename with no value'       bad-rename    $'rename\n' \
        'rename on line 1 of'
refuses 'rename with no colon'       bad-nocolon   $'rename old\n' \
        "needs exactly one colon: 'old'"
refuses 'rename with two colons'     bad-twocolon  $'rename old:new:extra\n' \
        "needs exactly one colon: 'old:new:extra'"
refuses 'rename with no source'      bad-nosource  $'rename :new\n' \
        "has no source: ':new'"
refuses 'new-package with no value'  bad-newpkg    $'new-package\n' \
        'new-package on line 1 of'
refuses 'except with no value'       bad-except    $'except\n' \
        'except on line 1 of'
refuses 'maps that selects nothing'  bad-empty     $'# only a comment\n' \
        'selects nothing'
refuses 'a declaration on its own'   bad-onlynew   $'new-package lonely\n' \
        'selects nothing'
refuses 'an except on its own'       bad-onlyexc \
        $'except packaging/cage/PKGBUILD\n' 'selects nothing'
refuses 'an except naming nothing the monolith has' bad-excmiss \
        $'flatten packaging/cage\nexcept packaging/cage/nosuch\n' \
        'packaging/cage/nosuch, which the monolith does not have'
refuses 'an except that leaves nothing behind' bad-excall \
        $'flatten packaging/cage\nexcept packaging/cage\n' \
        'kept no commits'
refuses 'roots that match nothing'   bad-roots     $'path nowhere/\n' \
        'kept no commits'
refuses 'a monolith that is not one' bad-mono      $'path packaging/cage/\n' \
        'is not a git repository' "$WORK/not-a-repo"

# --- the carves -------------------------------------------------------------

section 'flatten (the shape cage uses)'

if carve cage "$(maps cage $'flatten packaging/cage\n')"; then
    ok 'carve succeeded'
    check 'PKGBUILD and patch sit at the root' \
        [ "$(pushed_paths cage)" = '0001.patch PKGBUILD ' ]
    check 'only the commits that touched cage survive' \
        [ "$(pushed_commits cage)" = 2 ]
    check 'the monolith release tags are gone' \
        [ "$(pushed_tags cage)" = 0 ]
    check 'the pre-push check reported what it measured' \
        grep -qx 'verified 2 commits and 2 paths against .*/cage.paths' "$WORK/cage.out"
    check 'nothing unrelated came along' \
        grep -qv unrelated <<<"$(pushed_paths cage)"
else
    bad 'carve succeeded'
    cat "$WORK/cage.out"
fi

section 'a package the monolith does not build'

# The declaration is for the version check, which pairs a carved repo with the
# monolith PKGBUILD it came from and has none to pair a new name against. The
# carve reads it as nothing at all.
if carve cage-new "$(maps cage-new $'new-package cage\nflatten packaging/cage\n')"; then
    ok 'carve succeeded'
    check 'declaring a new package selects nothing extra' \
        [ "$(pushed_paths cage-new)" = '0001.patch PKGBUILD ' ]
else
    bad 'carve succeeded'
    cat "$WORK/cage-new.out"
fi

section 'flatten composes with a second tree'

if carve cage2 "$(maps cage2 $'flatten packaging/cage\npath test/cage/\n')"; then
    ok 'carve succeeded'
    check 'the flattened package and the untouched suite are both there' \
        [ "$(pushed_paths cage2)" = '0001.patch PKGBUILD test/cage/run.sh ' ]
else
    bad 'carve succeeded'
    cat "$WORK/cage2.out"
fi

section 'rename'

# A rename on its own is a filter, not just a move: naming only the rename
# would keep the entire monolith.
if carve lib-rename "$(maps lib-rename $'rename old:new\n')"; then
    ok 'carve succeeded'
    check 'only the renamed tree is carved' \
        [ "$(pushed_paths lib-rename)" = 'new/lib.sh ' ]
    check 'the sibling that merely starts the same is left behind' \
        grep -qv oldies <<<"$(pushed_paths lib-rename)"
    check 'the commits from before the move came too' \
        grep -qx 'add lib while it still lives in old' <<<"$(subjects lib-rename)"
    check 'and the edit made while it still lived at the old path' \
        grep -qx 'edit lib in place' <<<"$(subjects lib-rename)"
else
    bad 'carve succeeded'
    cat "$WORK/lib-rename.out"
fi

# The form the maps files actually use: the destination as a path, the move as
# a rename beside it.
if carve lib-both "$(maps lib-both $'path new/\nrename old:new\n')"; then
    ok 'carve succeeded'
    check 'declaring the destination too changes nothing' \
        [ "$(pushed_paths lib-both)" = "$(pushed_paths lib-rename)" ]
    check 'blame still reaches the first commit' \
        grep -qx 'add lib while it still lives in old' <<<"$(subjects lib-both)"
else
    bad 'carve succeeded'
    cat "$WORK/lib-both.out"
fi

section 'except (the shape a package split between repos uses)'

if carve cage-part "$(maps cage-part \
        $'flatten packaging/cage\npath test/cage/\nexcept packaging/cage/0001.patch\n')"; then
    ok 'carve succeeded'
    check 'the excepted file is gone and the rest of the package is not' \
        [ "$(pushed_paths cage-part)" = 'PKGBUILD test/cage/run.sh ' ]
    check 'the commits that touched it are still there for what else they did' \
        grep -qx 'add the cage patch and its out-of-tree suite' \
            <<<"$(subjects cage-part)"
    check 'the pre-push check counted the paths that are left' \
        grep -qx 'verified 2 commits and 2 paths against .*/cage-part.paths' \
            "$WORK/cage-part.out"
else
    bad 'carve succeeded'
    cat "$WORK/cage-part.out"
fi

# Naming a directory takes the whole of it, the way the other directives match.
if carve cage-dir "$(maps cage-dir \
        $'flatten packaging/cage\npath test/cage/\nexcept test/cage\n')"; then
    ok 'carve succeeded'
    check 'a directory except takes everything under it' \
        [ "$(pushed_paths cage-dir)" = '0001.patch PKGBUILD ' ]
else
    bad 'carve succeeded'
    cat "$WORK/cage-dir.out"
fi

section 'the pre-push check catches a subtraction that did not happen'

# The stray check measures the carve against what the maps file selected, and
# an excepted path is selected by the directive it is being subtracted from —
# so it cannot see this one. Break the subtraction and the carve must still die.
BLIND=$WORK/carve-blind.sh
# shellcheck disable=SC2016  # matching carve.sh's text, not expanding it
sed 's|filter-repo --invert-paths "${excepts\[@\]}"|filter-repo --version >/dev/null|' \
    "$CARVE" > "$BLIND"
# shellcheck disable=SC2016
if grep -q -- '--invert-paths "${excepts\[@\]}"' "$BLIND"; then
    bad 'fault injection did not take — the harness is not testing what it thinks'
else
    ok 'fault injection took'
    rm -rf "$(bare_of blind)"
    git init -q --bare "$(bare_of blind)"
    SHEDOS_CARVE_REMOTE=$(bare_of blind) bash "$BLIND" "$MONO" blind \
        "$(maps blind $'flatten packaging/cage\nexcept packaging/cage/0001.patch\n')" \
        > "$WORK/blind.out" 2>&1
    blind_rc=$?
    check 'the carve that kept an excepted path is refused' [ "$blind_rc" -ne 0 ]
    check 'it names the path it should have subtracted' \
        grep -q '0001.patch' "$WORK/blind.out"
    check 'it refuses by name' \
        grep -q 'refusing to push blind' "$WORK/blind.out"
    check 'and nothing reached the remote' [ "$(pushed_refs blind)" = 0 ]
fi

section 'the pre-push check catches a carve that overreaches'

# Nothing a maps file can say gets past the argument builder, so the builder
# is broken here instead: a rename that renames without also filtering, which
# keeps the entire monolith.
BROKEN=$WORK/carve-broken.sh
# shellcheck disable=SC2016  # matching carve.sh's text, not expanding it
sed 's|args+=(--path "$old" --path-rename "$old:$new")|args+=(--path-rename "$old:$new")|' \
    "$CARVE" > "$BROKEN"
# shellcheck disable=SC2016
if grep -q -- '--path "$old"' "$BROKEN"; then
    bad 'fault injection did not take — the harness is not testing what it thinks'
else
    ok 'fault injection took'
    rm -rf "$(bare_of overreach)"
    git init -q --bare "$(bare_of overreach)"
    SHEDOS_CARVE_REMOTE=$(bare_of overreach) bash "$BROKEN" "$MONO" overreach \
        "$(maps overreach $'rename old:new\n')" > "$WORK/overreach.out" 2>&1
    broken_rc=$?
    check 'the broken carve is refused' [ "$broken_rc" -ne 0 ]
    check 'it names the paths it was never asked for' \
        grep -q 'carried 5 path(s) the maps file never asked for' "$WORK/overreach.out"
    check 'it refuses by name' \
        grep -q 'refusing to push overreach' "$WORK/overreach.out"
    check 'and nothing reached the remote' [ "$(pushed_refs overreach)" = 0 ]
fi

section 'a maps file with no trailing newline'

if carve nonl "$(maps nonl 'flatten packaging/cage')"; then
    ok 'carve succeeded'
    check 'the last directive was still read' \
        [ "$(pushed_paths nonl)" = '0001.patch PKGBUILD ' ]
else
    bad 'carve succeeded'
    cat "$WORK/nonl.out"
fi

section 'a source tree that is not level with its origin'

# Refused before the clone, so filter-repo never runs and the remote is never
# touched. carve.sh says "carving <target> in <dir>" the moment it starts, so
# the absence of that line is what proves nothing began.
refuses_stale() {
    local desc=$1 target=$2 mono=$3 want=$4
    if carve "$target" "$(maps "$target" $'flatten packaging/cage\n')" "$mono"; then
        bad "$desc — the carve succeeded"
        return
    fi
    if ! grep -qF "$want" "$WORK/$target.out"; then
        bad "$desc — died on something else: $(tail -1 "$WORK/$target.out")"
        return
    fi
    if grep -q '^carving ' "$WORK/$target.out"; then
        bad "$desc — refused only after it had started carving"
        return
    fi
    if (( $(pushed_refs "$target") != 0 )); then
        bad "$desc — died but had already pushed"
        return
    fi
    ok "$desc"
}

BEHIND=$WORK/mono-behind
git clone -q "$MONO_ORIGIN" "$BEHIND"
git -C "$MONO" commit -q --allow-empty -m 'a release the carve should not miss'
git -C "$MONO" push -q origin main
behind_head=$(git -C "$BEHIND" rev-parse HEAD)
origin_head=$(git -C "$MONO" rev-parse HEAD)

check 'the fixture really is one commit behind' \
    [ "$behind_head" != "$origin_head" ]
refuses_stale 'a source tree behind its origin is refused' \
    stale-behind "$BEHIND" "$behind_head"
check 'the refusal names the origin commit too' \
    grep -qF "$origin_head" "$WORK/stale-behind.out"

AHEAD=$WORK/mono-ahead
git clone -q "$MONO_ORIGIN" "$AHEAD"
git -C "$AHEAD" config user.email harness@shedos.invalid
git -C "$AHEAD" config user.name 'carve harness'
git -C "$AHEAD" commit -q --allow-empty -m 'a commit the origin has never seen'
refuses_stale 'a source tree ahead of its origin is refused' \
    stale-ahead "$AHEAD" "$(git -C "$AHEAD" rev-parse HEAD)"

NOREMOTE=$WORK/mono-noremote
git clone -q "$MONO_ORIGIN" "$NOREMOTE"
git -C "$NOREMOTE" remote remove origin
refuses_stale 'a source tree with no origin is refused' \
    stale-noremote "$NOREMOTE" 'no origin'

# The happy path is still a carve: $MONO was pushed to its origin above, so it
# is level and the check has to let it through.
git -C "$MONO" push -q origin main
if carve level "$(maps level $'flatten packaging/cage\n')"; then
    ok 'a source tree level with its origin still carves'
    check 'and it carved the same thing as before' \
        [ "$(pushed_paths level)" = '0001.patch PKGBUILD ' ]
else
    bad 'a source tree level with its origin still carves'
    cat "$WORK/level.out"
fi

# --- summary ----------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
