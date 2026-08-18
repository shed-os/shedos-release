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
    # With the history, because a package whose PKGBUILD pins no tag is
    # placed by finding the commit its release was built at.
    if ! repo_clone_history "$repo" "$dir"; then
        echo "draft: $repo could not be read" >&2
        exit 2
    fi
    while read -r path; do
        repo_file "$dir" HEAD "$path" "$WORK/pkgbuild" || continue
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
    done < <(repo_pkgbuilds "$dir" HEAD)
done < <(awk 'NF && $1 !~ /^#/' "$ALLOWLIST")

(( clashes == 0 )) || exit 2

# --- the draft --------------------------------------------------------------

holes=0

hole() { printf '# %s: %s\n' "$1" "$2"; holes=$((holes + 1)); }
note() { printf '# %s\n' "$1"; }

# The ref for a package whose PKGBUILD pins no usable tag: the commit its
# release was built at, with where that came from written beside it. The
# publisher records the commit of every request it serves, so a package
# published since then is placed by what was recorded; one published before is
# placed by reading the branch, and says so, because the two are not the same
# quality of answer and the reader is the one who decides whether that matters.
build_ref() {
    local repo=$1 path=$2 name=$3 pkgver=$4 pkgrel=$5 kind=$6 pinned=$7 file=$8
    local recorded='' matches='' commit=''

    recorded=$(channel_origin_commit "$file")
    if [[ -n $recorded ]]; then
        printf 'ref = "%s"\n' "$recorded"
        note "the commit the publisher recorded for this release"
        # Said out loud because it is the one input here that carries no
        # signature: the database is verified before a version or a checksum is
        # read off it, and this record is not. A reader weighing a recorded
        # answer against a derived one should know which of the two the channel
        # can vouch for.
        note "that record is not signed, unlike the database beside it"
        return
    fi

    IFS=$'\t' read -r matches commit \
        < <(repo_build_commit "$WORK/repos/$repo" "$path" "$pkgver" "$pkgrel")
    if (( matches == 0 )); then
        hole ref "no commit on $repo builds $name at $pkgver-$pkgrel"
        return
    fi
    printf 'ref = "%s"\n' "$commit"
    if (( matches > 1 )); then
        hole ref "$matches commits on $repo build $name at $pkgver-$pkgrel and this took the newest"
    else
        note "derived: the one commit on $repo whose $path says $pkgver-$pkgrel"
        case $kind in
            commit) note "its source pins $pinned, which is the fork rather than this tree" ;;
            none) note "it builds from a source that names no ref" ;;
            nosource) note "it builds from the checkout and declares no source" ;;
        esac
        note "this release predates the publisher recording what it was asked"
    fi
}

printf '# Drafted by tools/draft-manifest.sh from what the channel serves.\n'
printf '# Read it before committing it: the manifest is authored state.\n\n'
printf '[release]\n'
if [[ -n $version ]]; then
    printf 'version = "%s"\n' "$version"
else
    hole version 'the release names itself and this cannot read that off a channel'
fi

while IFS=$'\t' read -r name channel_version file sum; do
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
        repo_file "$WORK/repos/$repo" HEAD "$path" "$WORK/pkgbuild"
        IFS=$'\t' read -r kind ref < <(pkgbuild_source_ref "$WORK/pkgbuild" "$pkgver")
        if [[ $kind == tag && $ref != *'$'* ]]; then
            # A tag the PKGBUILD pins governs what gets built, so it is the ref
            # and it needs nothing derived.
            printf 'ref = "%s"\n' "$ref"
        else
            [[ $kind != tag ]] || note "$repo/$path pins $ref which names something this cannot expand"
            build_ref "$repo" "$path" "$name" "$pkgver" "$pkgrel" "$kind" "$ref" "$file"
        fi
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
