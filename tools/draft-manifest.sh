#!/usr/bin/env bash
# draft-manifest.sh [<release-version>]
#
# A first draft of the release manifest, on stdout, from what the channel
# serves and what the package repositories say about it. It is assistance and
# nothing more: the committed manifest is authored state that a person has read
# and stands behind, and this exists so that person is reading rather than
# transcribing eighteen sha256s.
#
# The versions and checksums come from the channel database, which is only
# taken once its signature verifies — drafting from an unsigned database would
# copy whatever a bad object claimed straight into the release definition. The
# repository and the tag come from the PKGBUILD the owning repository holds:
# which repository builds a package is a question the repositories answer, and
# the tag is the one its source pins.
#
# A field this cannot fill is left out with the reason in its place, and the
# run says so and exits non-zero. A drafted guess is the one thing worse than
# a hole, because the hole is the part a reviewer would have looked at.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
# shellcheck source=tools/lib-manifest.sh
source "$HERE/lib-manifest.sh"

ALLOWLIST=${SHEDOS_MANIFEST_ALLOWLIST:-$ROOT/publisher/allowlist.txt}
version=${1:-}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

[[ -f $ALLOWLIST ]] || { echo "draft: $ALLOWLIST does not exist" >&2; exit 2; }

served=$WORK/served.tsv
channel_database "$WORK" > "$served" || exit 2

# --- which repository builds what -------------------------------------------

# The allowlist is the list of repositories that may publish, so it is also the
# list of repositories that could have published any of this. It is read
# org-relative, the way the manifest writes it.
index=$WORK/index.tsv
: > "$index"
clashes=0

while read -r entry; do
    repo=${entry##*/}
    dir=$WORK/repos/$repo
    mkdir -p "$WORK/repos"
    if ! repo_clone "$repo" "$dir"; then
        echo "draft: $repo could not be read" >&2
        exit 2
    fi
    while read -r path; do
        repo_file "$dir" "$path" "$WORK/pkgbuild" || continue
        while read -r name; do
            [[ -n $name ]] || continue
            held=$(awk -F'\t' -v n="$name" '$1 == n { print $2; exit }' "$index")
            if [[ -n $held ]]; then
                echo "draft: $held and $repo both build $name" >&2
                clashes=$((clashes + 1))
                continue
            fi
            printf '%s\t%s\t%s\n' "$name" "$repo" "$path" >> "$index"
        done < <(pkgbuild_names "$WORK/pkgbuild" 2> /dev/null)
    done < <(repo_pkgbuilds "$dir")
done < <(awk 'NF && $1 !~ /^#/' "$ALLOWLIST")

(( clashes == 0 )) || exit 2

# --- the draft --------------------------------------------------------------

holes=0

hole() { printf '# %s: %s\n' "$1" "$2"; holes=$((holes + 1)); }

printf '# Drafted by tools/draft-manifest.sh from what the channel serves.\n'
printf '# Read it before committing it: the manifest is authored state.\n\n'
printf '[release]\n'
if [[ -n $version ]]; then
    printf 'version = "%s"\n' "$version"
else
    hole version 'the release names itself and this cannot read that off a channel'
fi

while IFS=$'\t' read -r name channel_version _ sum; do
    pkgver=${channel_version%-*}
    pkgrel=${channel_version##*-}
    repo=$(awk -F'\t' -v n="$name" '$1 == n { print $2; exit }' "$index")
    path=$(awk -F'\t' -v n="$name" '$1 == n { print $3; exit }' "$index")

    printf '\n[[package]]\n'
    printf 'name = "%s"\n' "$name"

    if [[ -z $repo ]]; then
        hole repo 'no repository on the publisher allowlist builds this'
        hole tag 'without a repository there is nothing to take a tag from'
    else
        printf 'repo = "%s"\n' "$repo"
        repo_file "$WORK/repos/$repo" "$path" "$WORK/pkgbuild"
        IFS=$'\t' read -r kind ref < <(pkgbuild_source_ref "$WORK/pkgbuild" "$pkgver")
        case $kind in
            tag)
                if [[ $ref == *'$'* ]]; then
                    hole tag "$repo/$path pins $ref which names something this cannot expand"
                else
                    printf 'tag = "%s"\n' "$ref"
                fi
                ;;
            commit) hole tag "$repo/$path pins commit $ref rather than a tag" ;;
            none) hole tag "$repo/$path pins a source that names no ref" ;;
            *) hole tag "$repo/$path declares no source and builds from the checkout" ;;
        esac
    fi

    printf 'pkgver = "%s"\n' "$pkgver"
    printf 'pkgrel = "%s"\n' "$pkgrel"
    printf 'sha256 = "%s"\n' "$sum"
done < "$served"

count=$(grep -c . "$served")
if (( holes )); then
    printf '\ndrafted %d package(s) with %d field(s) this could not fill\n' \
        "$count" "$holes" >&2
    exit 1
fi
printf '\ndrafted %d package(s)\n' "$count" >&2
