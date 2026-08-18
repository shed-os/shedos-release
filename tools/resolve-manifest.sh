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
#   tag      the repository carries the tag
#   pkgbuild the tag builds a package by that name
#   pkgver   the PKGBUILD at the tag is at that pkgver
#   pkgrel   the tag is not ahead of the release the channel serves
#   channel  the signed database serves that name at that version and sha256
#   bytes    the file the channel hands over hashes to that sha256
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
    local name=$1 repo=$2 tag=$3 pkgver=$4 pkgrel=$5
    local dir=$WORK/repos/$repo@$tag path='' version='' release='' commit='' rc=0

    commit=$(repo_tag_commit "$repo" "$tag") || rc=$?
    case $rc in
        0) ;;
        2) fault "$name" tag "$repo carries no tag $tag"; return ;;
        *) fault "$name" tag "$repo could not be read"; return ;;
    esac

    mkdir -p "$WORK/repos"
    repo_clone_tag "$repo" "$dir" "$tag" "$commit" \
        || { fault "$name" tag "$repo at $tag could not be read as tag $tag"; return; }

    if ! path=$(repo_pkgbuild_for "$dir" "$name" "$WORK/pkgbuild"); then
        fault "$name" pkgbuild "$repo at $tag builds no package called $name"
        return
    fi

    if ! version=$(pkgbuild_field "$WORK/pkgbuild" pkgver); then
        fault "$name" pkgver "$path at $tag names no pkgver"
    elif [[ $version != "$pkgver" ]]; then
        fault "$name" pkgver "$repo at $tag builds $version rather than $pkgver"
    fi

    # pkgrel is the only field the tag is allowed to disagree about, and only
    # downwards. The pipeline moves pkgrel past whatever the channel already
    # carries and pushes that back to the branch, so a tag cut before the last
    # rebuild is legitimately behind. A tag ahead of the channel is the real
    # finding: it says the channel is serving something older than the source
    # the manifest pins.
    if ! release=$(pkgbuild_field "$WORK/pkgbuild" pkgrel); then
        fault "$name" pkgrel "$path at $tag names no pkgrel"
    elif (( $(vercmp "$release" "$pkgrel") > 0 )); then
        fault "$name" pkgrel "$repo at $tag is at pkgrel $release ahead of the published $pkgrel"
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

while IFS=$'\t' read -r kind name repo tag pkgver pkgrel sum; do
    [[ $kind == package ]] || continue
    checked=$((checked + 1))
    before=$failed
    resolve_source "$name" "$repo" "$tag" "$pkgver" "$pkgrel"
    resolve_channel "$name" "$pkgver" "$pkgrel" "$sum"
    (( failed > before )) || printf 'ok %s %s-%s from %s %s\n' "$name" "$pkgver" "$pkgrel" "$repo" "$tag"
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
