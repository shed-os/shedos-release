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
#
# See carve-maps/README.md for how to write one.
set -euo pipefail

die() { printf 'carve: %s\n' "$*" >&2; exit 1; }

(( $# == 3 )) || die 'usage: carve.sh <monolith> <target-repo> <maps-file>'
mono=$1 target=$2 maps=$3
[[ -d $mono/.git ]] || die "$mono is not a git repository"
[[ -f $maps ]] || die "$maps does not exist"
remote=${SHEDOS_CARVE_REMOTE:-git@github.com:shed-os/$target.git}

# Each directive becomes filter-repo arguments.
args=()
lineno=0

# The `|| [[ -n $kind ]]` picks up a last line with no newline after it.
# Without it that directive vanishes, and a maps file down to no directives at
# all carves the entire monolith instead of failing.
while read -r kind rest || [[ -n $kind ]]; do
    lineno=$((lineno + 1))
    case $kind in
        '' | '#'*) continue ;;
        path | rename | flatten) ;;
        *) die "unknown directive '$kind' on line $lineno of $maps" ;;
    esac
    # An empty value reaches filter-repo as --path '', which matches every
    # path in the monolith.
    [[ -n $rest ]] || die "$kind on line $lineno of $maps has no value"

    case $kind in
        path)
            args+=(--path "$rest")
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
            ;;
        flatten)
            dir=${rest%/}
            args+=(--path "$dir/" --path-rename "$dir/:")
            ;;
    esac
done < "$maps"

(( ${#args[@]} > 0 )) || die "$maps selects nothing"

work=$(mktemp -d)
echo "carving $target in $work"
git clone --no-local "$mono" "$work/src"

# Release tags name a state of the whole monolith, so none of them mean
# anything once a single package is on its own. Renaming them out of the way
# and dropping them keeps them from surfacing as package releases.
git -C "$work/src" filter-repo "${args[@]}" --tag-rename '':'mono-'
git -C "$work/src" tag -l 'mono-*' | xargs -r -n1 git -C "$work/src" tag -d

git -C "$work/src" remote add origin "$remote"
git -C "$work/src" push -u origin main
echo "carved $target from $mono ($(git -C "$work/src" rev-list --count HEAD) commits)"
rm -rf "$work"
