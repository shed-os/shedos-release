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

die() { printf 'carve: %s\n' "$*" >&2; exit 1; }

(( $# == 3 )) || die 'usage: carve.sh <monolith> <target-repo> <maps-file>'
mono=$1 target=$2 maps=$3
[[ -d $mono/.git ]] || die "$mono is not a git repository"
[[ -f $maps ]] || die "$maps does not exist"
remote=${SHEDOS_CARVE_REMOTE:-git@github.com:shed-os/$target.git}

# Each directive becomes filter-repo arguments plus one src->dst prefix pair.
# The pairs are a model of what filter-repo was asked to do, and the check
# before the push measures the real result against them.
args=()
pairs=()
lineno=0

# The `|| [[ -n $kind ]]` picks up a last line with no newline after it.
# Without it that directive vanishes, and a maps file down to no directives at
# all carves the entire monolith instead of failing.
while read -r kind rest || [[ -n $kind ]]; do
    lineno=$((lineno + 1))
    case $kind in
        '' | '#'*) continue ;;
        path | rename | flatten | new-package) ;;
        *) die "unknown directive '$kind' on line $lineno of $maps" ;;
    esac
    # An empty value reaches filter-repo as --path '', which matches every
    # path in the monolith.
    [[ -n $rest ]] || die "$kind on line $lineno of $maps has no value"

    case $kind in
        path)
            args+=(--path "$rest")
            pairs+=("$rest"$'\t'"$rest")
            ;;
        rename)
            [[ ${rest//[^:]/} == ':' ]] \
                || die "rename on line $lineno of $maps needs exactly one colon: '$rest'"
            old=${rest%%:*}
            new=${rest#*:}
            [[ -n $old ]] || die "rename on line $lineno of $maps has no source: '$rest'"
            # --path-rename on its own is not a filter: it renames what it
            # matches and keeps everything else, so the whole monolith comes
            # along. Naming the source as a path too is what makes it a
            # filter, and it is also what keeps the commits from before the
            # move — matching only the destination silently starts the
            # history at the rename.
            args+=(--path "$old" --path-rename "$old:$new")
            pairs+=("$old"$'\t'"$new")
            ;;
        flatten)
            dir=${rest%/}
            args+=(--path "$dir/" --path-rename "$dir/:")
            pairs+=("$dir/"$'\t')
            ;;
        # Nothing to select: it is addressed to the version check.
        new-package) ;;
    esac
done < "$maps"

(( ${#args[@]} > 0 )) || die "$maps selects nothing"

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

work=$(mktemp -d)
echo "carving $target in $work"
git clone --no-local "$mono" "$work/src"

# Release tags name a state of the whole monolith, so none of them mean
# anything once a single package is on its own. Renaming them out of the way
# and dropping them keeps them from surfacing as package releases.
git -C "$work/src" filter-repo "${args[@]}" --tag-rename '':'mono-'
git -C "$work/src" tag -l 'mono-*' | xargs -r -n1 git -C "$work/src" tag -d

# --- measure the result against the maps file, before anything is pushed ---

# Where <src> lands once <dst> has been applied, for every monolith path on
# stdin. filter-repo matches whole path components rather than raw string
# prefixes — `path old` leaves `oldies/` alone — so this does too, and the
# expectation stays exactly as tight as the filter it is checking.
move() {
    local src=${1%/} dst=${2%/} line rest
    while IFS= read -r line; do
        if [[ $line == "$src" ]]; then rest=
        elif [[ $line == "$src"/* ]]; then rest=${line#"$src"/}
        else continue
        fi
        if [[ -z $rest ]]; then printf '%s\n' "$dst"
        elif [[ -z $dst ]]; then printf '%s\n' "$rest"
        else printf '%s/%s\n' "$dst" "$rest"
        fi
    done
}

paths_of() { git -C "$1" log --format= --name-only | sed '/^$/d' | LC_ALL=C sort -u; }

# A carve that matched nothing leaves the branch unborn, so rev-list has no
# HEAD to count and its own error would be the last word instead of ours.
commits=$(git -C "$work/src" rev-list --count HEAD 2>/dev/null) || commits=0
(( commits > 0 )) || die "the carve of $target kept no commits — check the roots in $maps"

mono_paths=$(paths_of "$mono")
expected=$(
    for pair in "${pairs[@]}"; do
        move "${pair%%$'\t'*}" "${pair#*$'\t'}" <<<"$mono_paths"
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
printf 'verified %d commits and %d paths against %s\n' \
    "$commits" "$(printf '%s\n' "$actual" | wc -l)" "$maps"

git -C "$work/src" remote add origin "$remote"
git -C "$work/src" push -u origin main
echo "carved $target from $mono ($commits commits)"
rm -rf "$work"
