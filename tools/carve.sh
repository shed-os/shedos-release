#!/usr/bin/env bash
# carve.sh <monolith> <target-repo> <maps-file>
#
# Lift one package out of the monolith into its own repository, history and
# blame intact, and push it to shed-os/<target-repo>.
#
# The maps file says which of the monolith belongs to the target. One
# directive per line:
#
#   path <dir>          keep <dir> where it sits
#   rename <old>:<new>  keep <old> and move it to <new>, so blame survives
#                       the renames a package picked up along the way
#   flatten <dir>       keep <dir> and lift its contents to the repo root
#
# flatten stands alone. A repo is either rooted in a single monolith
# directory or assembled out of several; mixing the two is a mistake in the
# maps file, not a thing to guess at.
set -euo pipefail

die() { printf 'carve: %s\n' "$*" >&2; exit 1; }

(( $# == 3 )) || die 'usage: carve.sh <monolith> <target-repo> <maps-file>'
mono=$1 target=$2 maps=$3
[[ -d $mono/.git ]] || die "$mono is not a git repository"
[[ -f $maps ]] || die "$maps does not exist"

args=()
flatten=
# The `|| [[ -n $kind ]]` picks up a last line with no newline after it.
# Without it that directive vanishes, and a maps file down to no directives
# at all carves the entire monolith instead of failing.
while read -r kind rest || [[ -n $kind ]]; do
    case $kind in
        '' | '#'*) ;;
        path) args+=(--path "$rest") ;;
        rename) args+=(--path-rename "${rest%%:*}:${rest##*:}") ;;
        flatten) flatten=$rest ;;
        *) die "unknown directive '$kind' in $maps" ;;
    esac
done < "$maps"

if [[ -n $flatten ]]; then
    (( ${#args[@]} == 0 )) || die "flatten cannot be mixed with other directives in $maps"
    args=(--subdirectory-filter "$flatten")
fi
(( ${#args[@]} > 0 )) || die "$maps selects nothing"

work=$(mktemp -d)
echo "carving $target in $work"
git clone --no-local "$mono" "$work/src"

# Release tags name a state of the whole monolith, so none of them mean
# anything once a single package is on its own. Renaming them out of the way
# and dropping them keeps them from surfacing as package releases.
git -C "$work/src" filter-repo "${args[@]}" --tag-rename '':'mono-'
git -C "$work/src" tag -l 'mono-*' | xargs -r -n1 git -C "$work/src" tag -d

git -C "$work/src" remote add origin "git@github.com:shed-os/$target.git"
git -C "$work/src" push -u origin main
echo "carved $target from $mono ($(git -C "$work/src" rev-list --count HEAD) commits)"
rm -rf "$work"
