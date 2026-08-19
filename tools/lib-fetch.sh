# shellcheck shell=bash
# Turning a release manifest into files on disk. The ISO bakes what the
# manifest names and nothing else, so every ShedOS package that goes into it
# comes down from the channel and is held to the sha the manifest wrote down
# before anything is allowed to read it. Sourced, never run.
#
# The manifest is the authority on which release a package is, and the signed
# database is the authority on which file that release is served as. Both are
# consulted: the database says the filename and the manifest says the bytes,
# and a disagreement between them is a refusal rather than a preference.
#
# SHEDOS_PACKAGE_CACHE names a directory kept across calls. A cached file is
# reused only when it hashes to the sha the manifest names, so a truncated
# download or a stale file from an earlier release is refetched rather than
# trusted.

_LIB_FETCH_HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=tools/lib-manifest.sh
source "$_LIB_FETCH_HERE/lib-manifest.sh"

# The manifest and the channel read together, as one
# "<name>\t<pkgver>\t<pkgrel>\t<file>\t<sha256>" line per manifest entry on
# stdout. $2 is a scratch directory the database and its keyring land in.
#
# Every entry has to hold on all three axes — the channel serves the name, at
# that version, recording that sha — because a fetch stage that fell back to
# whatever the channel happens to serve would build an ISO out of a release
# nobody defined. What it does NOT check is the source side: that is
# resolve-manifest.sh's question and it is asked of the whole manifest, not of
# the subset an ISO needs.
manifest_serving() {
    local manifest=$1 work=$2
    local parsed=$work/manifest.tsv served=$work/served.tsv
    local row name repo ref pkgver pkgrel sum entry version file recorded
    local failed=0

    manifest_read "$manifest" > "$parsed" || return 2
    channel_database "$work" > "$served" || return 2

    while IFS=$'\t' read -r row name repo ref pkgver pkgrel sum; do
        [[ $row == package ]] || continue
        entry=$(awk -F'\t' -v n="$name" '$1 == n { print; exit }' "$served")
        if [[ -z $entry ]]; then
            echo "fetch: the channel serves no $name" >&2
            failed=1
            continue
        fi
        IFS=$'\t' read -r _ version file recorded <<<"$entry"
        if [[ $version != "$pkgver-$pkgrel" ]]; then
            echo "fetch: the channel serves $name $version rather than $pkgver-$pkgrel" >&2
            failed=1
            continue
        fi
        if [[ $recorded != "$sum" ]]; then
            echo "fetch: the database records $recorded for $file, the manifest names $sum" >&2
            failed=1
            continue
        fi
        printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$pkgver" "$pkgrel" "$file" "$sum"
    done < "$parsed"

    (( failed == 0 ))
}

# One package file into $3, from the cache when the cache has it at that sha
# and from the channel otherwise. The sha is checked after every path into the
# file, including the cached one: a cache is a place bytes sit unattended.
fetch_package_file() {
    local file=$1 sum=$2 dest=$3 cache=${SHEDOS_PACKAGE_CACHE:-} got=''

    if [[ -n $cache && -f $cache/$file ]]; then
        got=$(sha256sum "$cache/$file" | cut -d' ' -f1)
        if [[ $got == "$sum" ]]; then
            cp -- "$cache/$file" "$dest"
            printf 'cache\n'
            return 0
        fi
        rm -f -- "$cache/$file"
    fi

    channel_fetch "$CHANNEL_URL" "$file" "$dest" || {
        echo "fetch: the channel would not hand over $file" >&2
        return 1
    }
    got=$(sha256sum "$dest" | cut -d' ' -f1)
    if [[ $got != "$sum" ]]; then
        rm -f -- "$dest"
        echo "fetch: $file hashes to $got rather than $sum" >&2
        return 1
    fi
    if [[ -n $cache ]]; then
        mkdir -p "$cache"
        cp -- "$dest" "$cache/$file"
    fi
    printf 'channel\n'
}

# Every package the manifest names, into $2. Prints one line per package
# naming where the bytes came from and the sha they were held to, because that
# line is the evidence a release build is asked for afterwards.
fetch_manifest_packages() {
    local manifest=$1 into=$2 work='' rc=0
    local name pkgver pkgrel file sum where

    work=$(mktemp -d)
    mkdir -p "$into"
    # The status has to be read off the call itself. Asking for it inside an
    # `if !` reads the negation's status, which is zero however the call went,
    # and a fetch stage that always succeeded would be the worst of the
    # failures this returns codes for.
    manifest_serving "$manifest" "$work" > "$work/wanted.tsv"
    rc=$?
    if (( rc != 0 )); then
        rm -rf "$work"
        return $rc
    fi

    while IFS=$'\t' read -r name pkgver pkgrel file sum; do
        if where=$(fetch_package_file "$file" "$sum" "$into/$file"); then
            printf 'ok %s %s-%s %s sha256=%s from the %s\n' \
                "$name" "$pkgver" "$pkgrel" "$file" "$sum" "$where"
        else
            rc=1
        fi
    done < "$work/wanted.tsv"

    rm -rf "$work"
    return $rc
}

# One named package out of the manifest, unpacked into $3. This is how anything
# that needs to read shipped code reaches it now: the harnesses that used to
# source it out of a working tree, and the release checks that compare what
# several packages ship. What comes out is what the release ships, which is the
# only copy worth asserting against.
#
# The package metadata files are left in place — .PKGINFO is what a dependency
# check reads — and the caller gets the directory it asked for.
extract_manifest_package() {
    local manifest=$1 name=$2 into=$3 work='' rc=0
    local got pkgver pkgrel file sum found=''

    work=$(mktemp -d)
    manifest_serving "$manifest" "$work" > "$work/wanted.tsv"
    rc=$?
    if (( rc != 0 )); then
        rm -rf "$work"
        return $rc
    fi

    while IFS=$'\t' read -r got pkgver pkgrel file sum; do
        [[ $got == "$name" ]] || continue
        found=$file
        break
    done < "$work/wanted.tsv"

    if [[ -z $found ]]; then
        echo "fetch: the manifest names no $name" >&2
        rm -rf "$work"
        return 1
    fi

    if ! fetch_package_file "$found" "$sum" "$work/$found" > /dev/null; then
        rm -rf "$work"
        return 1
    fi

    mkdir -p "$into"
    if ! bsdtar -xf "$work/$found" -C "$into"; then
        echo "fetch: $found could not be unpacked" >&2
        rc=1
    fi
    rm -rf "$work"
    return $rc
}
