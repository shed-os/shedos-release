#!/usr/bin/env bash
# carve.sh <monolith> <target-repo> <maps-file>
#
# Lift one package out of the monolith into its own repository, history and
# blame intact, and push it to shed-os/<target-repo>. Set SHEDOS_CARVE_REMOTE
# to push somewhere else.
#
# The maps file says which of the monolith belongs to the target. One
# directive per line, and they compose freely:
#
#   path <dir>          keep <dir> where it sits
#   rename <old>:<new>  keep <old> too and move it to <new>, so the commits
#                       from before the move stay with the file
#   flatten <dir>       keep <dir> and lift its contents to the repo root
#   except <path>       leave <path> behind, whatever else asked for it
#   new-package <name>  <name> is a package the monolith does not build, so
#                       nothing pairs it with one
#
# See carve-maps/README.md for how to write one.
#
# Nothing is pushed until the rewritten history has been measured against the
# maps file: a carve that kept more of the monolith than it was told to dies
# here, where the fix is to edit the maps file and run again, rather than on
# the remote where the only way out is a force-push.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=tools/lib-carve-maps.sh
source "$HERE/lib-carve-maps.sh"

die() { printf 'carve: %s\n' "$*" >&2; exit 1; }

(( $# == 3 )) || die 'usage: carve.sh <monolith> <target-repo> <maps-file>'
mono=$1 target=$2 maps=$3
[[ -d $mono/.git ]] || die "$mono is not a git repository"
[[ -f $maps ]] || die "$maps does not exist"
remote=${SHEDOS_CARVE_REMOTE:-git@github.com:shed-os/$target.git}

# Each directive becomes filter-repo arguments plus one src->dst prefix pair.
# The pairs are a model of what filter-repo was asked to do, and the check
# before the push measures the real result against them.
read_map "$maps" || die "$MAP_ERROR"
args=("${MAP_ARGS[@]}")
pairs=("${MAP_PAIRS[@]}")
excepted=("${MAP_EXCEPTS[@]}")
excepts=()
for path in "${excepted[@]}"; do
    excepts+=(--path "$path")
done

(( ${#args[@]} > 0 )) || die "$maps selects nothing"

paths_of() { git -C "$1" log --format= --name-only | sed '/^$/d' | LC_ALL=C sort -u; }

# The carve is a copy of this tree's history, so it has to be exactly where its
# own origin is. Behind carves a package the release has already moved past and
# every later check agrees with it, because they all read the same stale tree.
# Ahead is the same problem from the other side: commits nobody else has.
source_url=$(git -C "$mono" config --get remote.origin.url) \
    || die "$mono has no origin to check its history against"
remote_head=$(git -C "$mono" ls-remote "$source_url" HEAD) \
    || die "could not reach $mono's origin at $source_url"
remote_head=${remote_head%%[[:space:]]*}
[[ -n $remote_head ]] || die "$mono's origin at $source_url names no HEAD"
local_head=$(git -C "$mono" rev-parse HEAD)
[[ $local_head == "$remote_head" ]] \
    || die "$mono is at $local_head and its origin is at $remote_head"

mono_paths=$(paths_of "$mono")

# An except naming a path the monolith never had subtracts nothing and reads
# as a subtraction that worked, which is the whole failure this directive is
# there to prevent. Expanding each one against the monolith is also what the
# check after the carve needs: it has to look for files, not for the directory
# a directive may have named.
excepted_files=()
for path in "${excepted[@]}"; do
    mapfile -t hits < <(map_move "$path" "$path" <<<"$mono_paths")
    (( ${#hits[@]} > 0 )) \
        || die "$maps excepts $path, which the monolith does not have"
    excepted_files+=("${hits[@]}")
done

work=$(mktemp -d)
echo "carving $target in $work"
git clone --no-local "$mono" "$work/src"

# Subtraction first, in the monolith's own path names, so the pass below sees
# the tree the maps file means and a rename still replays from the source path
# the monolith used rather than from wherever the subtraction left things.
if (( ${#excepts[@]} > 0 )); then
    git -C "$work/src" filter-repo --invert-paths "${excepts[@]}"
fi

# Release tags name a state of the whole monolith, so none of them mean
# anything once a single package is on its own. Renaming them out of the way
# and dropping them keeps them from surfacing as package releases. --force
# because a subtraction above leaves this no longer looking like a fresh clone.
git -C "$work/src" filter-repo "${args[@]}" --tag-rename '':'mono-' --force
git -C "$work/src" tag -l 'mono-*' | xargs -r -n1 git -C "$work/src" tag -d

# --- measure the result against the maps file, before anything is pushed ---

# A carve that matched nothing leaves the branch unborn, so rev-list has no
# HEAD to count and its own error would be the last word instead of ours.
commits=$(git -C "$work/src" rev-list --count HEAD 2>/dev/null) || commits=0
(( commits > 0 )) || die "the carve of $target kept no commits — check the roots in $maps"

expected=$(
    for pair in "${pairs[@]}"; do
        map_move "${pair%%$'\t'*}" "${pair#*$'\t'}" <<<"$mono_paths"
    done | LC_ALL=C sort -u
)
actual=$(paths_of "$work/src")
stray=$(LC_ALL=C comm -23 <(printf '%s\n' "$actual") <(printf '%s\n' "$expected"))
if [[ -n $stray ]]; then
    printf 'carve: %s carried %d path(s) the maps file never asked for:\n' \
        "$target" "$(wc -l <<<"$stray")" >&2
    head -5 <<<"$stray" | sed 's/^/  /' >&2
    die "refusing to push $target"
fi

# The stray check cannot see a subtraction that did not happen: it measures the
# carve against what the directives selected, and an excepted path is selected
# by the very directive it is being taken out of. So the excepted paths are
# looked for by name, wherever the renames would have put them.
kept=$(
    for path in "${excepted_files[@]}"; do
        for pair in "${pairs[@]}"; do
            map_move "${pair%%$'\t'*}" "${pair#*$'\t'}" <<<"$path"
        done
    done | LC_ALL=C sort -u | LC_ALL=C comm -12 - <(printf '%s\n' "$actual")
)
if [[ -n $kept ]]; then
    printf 'carve: %s kept %d path(s) the maps file excepted:\n' \
        "$target" "$(wc -l <<<"$kept")" >&2
    head -5 <<<"$kept" | sed 's/^/  /' >&2
    die "refusing to push $target"
fi
printf 'verified %d commits and %d paths against %s\n' \
    "$commits" "$(printf '%s\n' "$actual" | wc -l)" "$maps"

git -C "$work/src" remote add origin "$remote"
git -C "$work/src" push -u origin main
echo "carved $target from $mono ($commits commits)"
rm -rf "$work"
