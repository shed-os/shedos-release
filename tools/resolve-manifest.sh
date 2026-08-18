#!/usr/bin/env bash
# resolve-manifest.sh <release-manifest.toml>
#
# Every pin in the manifest, checked against the two things it claims about:
# the package repository the source came from, and the channel the package
# went to. A manifest is a promise that a release can be rebuilt and refetched
# from what it names, and nothing else in the repo asks whether that promise
# still holds.
#
# Six axes, each named on its own so a failure says which half of the pin
# moved:
#
#   ref      the repository carries the tag, or the commit
#   pkgbuild the ref builds a package by that name
#   pkgver   the PKGBUILD at the ref is at that pkgver
#   pkgrel   a tag is not ahead of the release the channel serves; a commit is
#            that release exactly
#   channel  the signed database serves that name at that version and sha256
#   bytes    the file the channel hands over hashes to that sha256
#
# A ref is a tag where a tag governs the build and the commit the build used
# where none does, and the two are held to different pkgrel rules on purpose. A
# tag names the source a PKGBUILD pins, and the pipeline moves pkgrel past the
# channel without moving the tag, so a tag legitimately lags. A commit names
# the tree the package was built from, and that tree carries the released
# pkgrel or it is not the tree.
#
# It reports everything it found rather than stopping at the first thing, and
# it never repairs the manifest: what is written down is the answer, and this
# says whether the world still agrees with it.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=tools/lib-manifest.sh
source "$HERE/lib-manifest.sh"

(( $# == 1 )) || { echo 'usage: resolve-manifest.sh <release-manifest.toml>' >&2; exit 2; }
manifest=$1
[[ -f $manifest ]] || { echo "resolve: $manifest does not exist" >&2; exit 2; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Exit 2 is "the check could not be made" and exit 1 is "a pin does not hold".
# Reading them as one answer would let an unreachable channel pass for a clean
# release definition.
parsed=$WORK/manifest.tsv
manifest_read "$manifest" > "$parsed" || exit 2

served=$WORK/served.tsv
channel_database "$WORK" > "$served" || exit 2

failed=0
checked=0

fault() { printf '%s: %s: %s\n' "$1" "$2" "$3"; failed=$((failed + 1)); }

# The tag half. The repository is read once per tag however many packages the
# manifest pins to it, because a repository holding five packages holds them at
# one tag.
resolve_source() {
    local name=$1 repo=$2 ref=$3 pkgver=$4 pkgrel=$5
    local dir=$WORK/repos/$repo@$ref path='' version='' release='' commit='' rc=0
    local kind='' rev=''

    kind=$(ref_kind "$ref")
    mkdir -p "$WORK/repos"

    if [[ $kind == tag ]]; then
        commit=$(repo_tag_commit "$repo" "$ref") || rc=$?
        case $rc in
            0) ;;
            2) fault "$name" ref "$repo carries no tag $ref"; return ;;
            *) fault "$name" ref "$repo could not be read"; return ;;
        esac
        repo_clone_tag "$repo" "$dir" "$ref" "$commit" \
            || { fault "$name" ref "$repo at $ref could not be read as tag $ref"; return; }
        rev=HEAD
    else
        repo_clone_commit "$repo" "$dir" "$ref" \
            || { fault "$name" ref "$repo carries no commit $ref"; return; }
        rev=$ref
    fi

    if ! path=$(repo_pkgbuild_for "$dir" "$rev" "$name" "$WORK/pkgbuild"); then
        fault "$name" pkgbuild "$repo at $ref builds no package called $name"
        return
    fi

    if ! version=$(pkgbuild_field "$WORK/pkgbuild" pkgver); then
        fault "$name" pkgver "$path at $ref names no pkgver"
    elif [[ $version != "$pkgver" ]]; then
        fault "$name" pkgver "$repo at $ref builds $version rather than $pkgver"
    fi

    if ! release=$(pkgbuild_field "$WORK/pkgbuild" pkgrel); then
        fault "$name" pkgrel "$path at $ref names no pkgrel"
    elif [[ $kind == commit ]]; then
        # The commit is the tree the package was built from, so it carries the
        # released pkgrel exactly. Anything else means the manifest is pointing
        # at a tree that built something other than what the channel serves.
        [[ $release == "$pkgrel" ]] \
            || fault "$name" pkgrel "$repo at $ref is at pkgrel $release rather than the published $pkgrel"
    elif (( $(vercmp "$release" "$pkgrel") > 0 )); then
        # A tag names the source a PKGBUILD pins rather than the tree it was
        # built in, and the pipeline moves pkgrel past whatever the channel
        # already carries without moving the tag — so behind is ordinary. Ahead
        # is the real finding: it says the channel is serving something older
        # than the source the manifest pins.
        fault "$name" pkgrel "$repo at $ref is at pkgrel $release ahead of the published $pkgrel"
    fi
}

# The channel half.
resolve_channel() {
    local name=$1 pkgver=$2 pkgrel=$3 sum=$4
    local entry='' version='' file='' recorded='' got='' out=$WORK/package.pkg.tar.zst

    entry=$(awk -F'\t' -v n="$name" '$1 == n { print; exit }' "$served")
    if [[ -z $entry ]]; then
        fault "$name" channel "the channel serves no $name"
        return
    fi
    IFS=$'\t' read -r _ version file recorded <<<"$entry"

    if [[ $version != "$pkgver-$pkgrel" ]]; then
        fault "$name" channel "the channel serves $name $version rather than $pkgver-$pkgrel"
        return
    fi
    if [[ $recorded != "$sum" ]]; then
        fault "$name" channel "the database records $recorded for $file"
        return
    fi

    # The database is signed and the manifest agrees with it, which is not the
    # same as the bytes being right: what a later build fetches is the file,
    # not the record of it.
    if ! channel_fetch "$CHANNEL_URL" "$file" "$out"; then
        fault "$name" bytes "the channel would not hand over $file"
        return
    fi
    got=$(sha256sum "$out" | cut -d' ' -f1)
    rm -f "$out"
    [[ $got == "$sum" ]] || fault "$name" bytes "$file hashes to $got"
}

release_version=$(awk -F'\t' '$1 == "release" { print $2; exit }' "$parsed")
printf 'release %s\n' "$release_version"

while IFS=$'\t' read -r row name repo ref pkgver pkgrel sum; do
    [[ $row == package ]] || continue
    checked=$((checked + 1))
    before=$failed
    resolve_source "$name" "$repo" "$ref" "$pkgver" "$pkgrel"
    resolve_channel "$name" "$pkgver" "$pkgrel" "$sum"
    (( failed > before )) || printf 'ok %s %s-%s from %s %s\n' "$name" "$pkgver" "$pkgrel" "$repo" "$ref"
done < "$parsed"

# A package in the channel that the manifest does not name is a note rather
# than a failure: nothing is ever deleted from a channel, so a release is free
# to leave a retired package behind. It is still worth saying, because the
# other reason for one is a release definition that forgot a package.
while IFS=$'\t' read -r name _; do
    awk -F'\t' -v n="$name" '$1 == "package" && $2 == n { found = 1 }
                             END { exit !found }' "$parsed" && continue
    printf 'note: the channel serves %s which the manifest does not name\n' "$name"
done < "$served"

if (( failed )); then
    printf '\n%d of %d pin(s) did not hold\n' "$failed" "$checked"
    exit 1
fi
printf '\nall %d pin(s) hold\n' "$checked"
