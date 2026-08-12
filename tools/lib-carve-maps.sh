#!/usr/bin/env bash
# What a carve map says about a package, for the two things that ask: the
# version check and the reference build. Sourced, never run.

MONOLITH_RAW=https://raw.githubusercontent.com/Theshedman/shedos/main
CARVED_RAW=https://raw.githubusercontent.com/shed-os
# Cloudflare's managed rules drop datacenter traffic that does not name itself,
# and a GitHub runner is a datacenter address.
USER_AGENT='shedos-release (+https://shedos.org)'

# Read, never sourced: a PKGBUILD is a shell script and these come off the
# network. An empty answer is refused rather than compared, or a pkgver built in
# a pkgver() function would read as empty on both sides and match.
pkgbuild_field() {
    local value
    value=$(sed -n "s/^$2=//p" "$1" | head -1 | tr -d "\"'")
    [[ -n $value ]] || return 1
    printf '%s\n' "$value"
}

rename_dest() {
    awk -v root="$2" '$1 == "rename" {
        colon = index($2, ":")
        src = substr($2, 1, colon - 1)
        dst = substr($2, colon + 1)
        sub(/\/+$/, "", src); sub(/\/+$/, "", dst)
        if (src == root) print dst
    }' "$1" | head -1
}

# One "<repo> <packaging dir> [subdir]" line per package, written to $1, from
# the maps in $2. The repo is the maps file's name and the packaging dir is
# whichever directive names one. A rename contributes its destination, because
# that is where the monolith holds the package now — and because the clearer
# form writes `path new` beside it, which would otherwise read as two packaging
# directories rather than one.
#
# The subdirectory is where the carved repo keeps the PKGBUILD, empty for the
# root. A rename out of the package's own directory is what says so: a repo
# whose own source holds the root takes the package build one level down.
#
# Several packaging directories is one pair each, and every one of them has to
# name a destination of its own. That is what separates packages sharing a repo
# from a map that is ambiguous about which of two directories the package is.
#
# $3 is the maps that carve something other than a package, one name per line.
# A maps file naming no packaging directory has to be listed there; this
# refuses to guess which it is.
derive_pairs() {
    local out=$1 dir=$2 exempt=${3:-} file repo roots count root subdir taken

    shopt -s nullglob
    local maps=("$dir"/*.paths)
    shopt -u nullglob
    (( ${#maps[@]} > 0 )) || { echo "no carve maps in $dir"; return 2; }

    for file in "${maps[@]}"; do
        repo=$(basename "$file" .paths)
        roots=$(awk '$1 == "path" || $1 == "flatten" { print $2 }
                     $1 == "rename" { sub(/.*:/, "", $2); print $2 }' "$file" \
                | sed 's:/*$::' | grep '^packaging/' | LC_ALL=C sort -u)
        count=0
        [[ -z $roots ]] || count=$(grep -c . <<<"$roots")

        if (( count == 0 )); then
            grep -qxF "$repo" <<<"$exempt" && continue
            echo "$repo.paths carves no packaging directory and is not listed as exempt"
            return 2
        fi

        taken=''
        for root in $roots; do
            subdir=$(rename_dest "$file" "$root")
            if (( count > 1 )) &&
                    { [[ -z $subdir ]] || grep -qxF "$subdir" <<<"$taken"; }; then
                echo "$repo.paths carves $count packaging directories and one has to be the package"
                return 2
            fi
            taken+=$'\n'$subdir
            printf '%s %s %s\n' "$repo" "$root" "$subdir" >> "$out"
        done
    done
}

# 0 it is there, 3 there is no PKGBUILD at that path, 1 it could not be read.
# A directory holding no package and a fetch that failed have to stay different
# answers, or a caller goes blind exactly where it should stop.
read_pkgbuild() {
    local dir=$1 key=$2 url=$3 out=$4 code
    if [[ -n $dir ]]; then
        [[ -f $dir/$key/PKGBUILD ]] || return 3
        cp -- "$dir/$key/PKGBUILD" "$out" 2>/dev/null || return 1
        return 0
    fi
    code=$(curl -sSL --max-time 60 -A "$USER_AGENT" -o "$out" -w '%{http_code}' "$url") \
        || return 1
    [[ $code == 404 ]] && return 3
    [[ $code == 2?? ]]
}
