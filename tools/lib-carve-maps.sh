#!/usr/bin/env bash
# What a carve map says about a package, for the things that ask: the version
# check, the reference build, the carve itself and the walk that measures its
# result. Sourced, never run.

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

# What a maps file selects, read once for every tool that has to agree about
# it. MAP_PAIRS gets one "<src>\t<dst>" per selecting directive, MAP_EXCEPTS
# the paths left behind, and MAP_ARGS the filter-repo arguments the pairs
# stand for. A malformed file sets MAP_ERROR and returns 2 instead of
# exiting, so each caller — carve.sh and the enumeration walk both read it —
# keeps its own voice.
#
# The `|| [[ -n $kind ]]` picks up a last line with no newline after it.
# Without it that directive vanishes, and a maps file down to no directives at
# all selects the entire monolith instead of failing.
read_map() {
    local maps=$1 kind rest lineno=0 old new dir
    MAP_PAIRS=() MAP_EXCEPTS=() MAP_ARGS=()
    MAP_ERROR=''

    while read -r kind rest || [[ -n $kind ]]; do
        lineno=$((lineno + 1))
        case $kind in
            '' | '#'*) continue ;;
            path | rename | flatten | except | new-package) ;;
            *) MAP_ERROR="unknown directive '$kind' on line $lineno of $maps"; return 2 ;;
        esac
        # An empty value reaches filter-repo as --path '', which matches every
        # path in the monolith.
        [[ -n $rest ]] || { MAP_ERROR="$kind on line $lineno of $maps has no value"; return 2; }

        case $kind in
            path)
                MAP_ARGS+=(--path "$rest")
                MAP_PAIRS+=("$rest"$'\t'"$rest")
                ;;
            rename)
                [[ ${rest//[^:]/} == ':' ]] || {
                    MAP_ERROR="rename on line $lineno of $maps needs exactly one colon: '$rest'"
                    return 2
                }
                old=${rest%%:*}
                new=${rest#*:}
                [[ -n $old ]] || {
                    MAP_ERROR="rename on line $lineno of $maps has no source: '$rest'"
                    return 2
                }
                # --path-rename on its own is not a filter: it renames what it
                # matches and keeps everything else, so the whole monolith comes
                # along. Naming the source as a path too is what makes it a
                # filter, and it is also what keeps the commits from before the
                # move — matching only the destination silently starts the
                # history at the rename.
                MAP_ARGS+=(--path "$old" --path-rename "$old:$new")
                MAP_PAIRS+=("$old"$'\t'"$new")
                ;;
            flatten)
                dir=${rest%/}
                MAP_ARGS+=(--path "$dir/" --path-rename "$dir/:")
                MAP_PAIRS+=("$dir/"$'\t')
                ;;
            except)
                MAP_EXCEPTS+=("${rest%/}")
                ;;
            # Nothing to select: it is addressed to the version check, which
            # reads the directive out of the file rather than from here.
            new-package) ;;
        esac
    done < "$maps"
}

# Every path on stdin that <src> matches, printed as "<path>\t<where it lands
# once <dst> has been applied>". filter-repo matches whole path components
# rather than raw string prefixes — `path old` takes `old/` and a file named
# exactly `old`, and leaves `oldies/` alone — so this does too, and every
# expectation built on it stays exactly as tight as the filter it describes.
map_move_from() {
    local src=${1%/} dst=${2%/} line rest
    while IFS= read -r line; do
        if [[ $line == "$src" ]]; then rest=
        elif [[ $line == "$src"/* ]]; then rest=${line#"$src"/}
        else continue
        fi
        if [[ -z $rest ]]; then printf '%s\t%s\n' "$line" "$dst"
        elif [[ -z $dst ]]; then printf '%s\t%s\n' "$line" "$rest"
        else printf '%s\t%s/%s\n' "$line" "$dst" "$rest"
        fi
    done
}

# The same match for the callers that only want the destination.
map_move() { map_move_from "$@" | cut -f2; }

# Where each of the sorted paths in $1 lands, as "<path>\t<destination>", given
# the pairs read_map last read. filter-repo renames what survives the filter
# and the first --path-rename that matches a path is the one that moves it, so
# a `path` beside a `rename` of the same directory selects the files while the
# rename alone says where they go. A path no rename matches stays where it is.
map_place() {
    local remaining=$1 pair src dst matched
    for pair in "${MAP_PAIRS[@]}"; do
        src=${pair%%$'\t'*}
        dst=${pair#*$'\t'}
        [[ $src != "$dst" ]] || continue
        [[ -n $remaining ]] || return 0
        matched=$(map_move_from "$src" "$dst" <<<"$remaining")
        [[ -n $matched ]] || continue
        printf '%s\n' "$matched"
        remaining=$(LC_ALL=C comm -23 <(printf '%s\n' "$remaining") \
            <(cut -f1 <<<"$matched" | LC_ALL=C sort -u))
    done
    [[ -n $remaining ]] || return 0
    awk -F'\n' '{ printf "%s\t%s\n", $0, $0 }' <<<"$remaining"
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
# A `new-package` directive is the other way a maps file names no packaging
# directory: the carve makes a package the monolith has never built, so there is
# no PKGBUILD on the other side to compare against. It contributes no pair and
# says so, because a package silently absent from the comparison is a package
# nothing guards.
#
# $3 is the maps that carve something other than a package, one name per line.
# A maps file naming no packaging directory has to be listed there; this
# refuses to guess which it is. MAPS_NOT_PACKAGES is what the callers that
# have no reason to differ pass: shedos-release's map carves the package
# lists and the two generators that read them, and builds nothing.
MAPS_NOT_PACKAGES='shedos-release'

derive_pairs() {
    local out=$1 dir=$2 exempt=${3:-} file repo roots count root subdir taken new

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

        new=$(awk '$1 == "new-package" { print $2 }' "$file")
        if [[ -n $new ]]; then
            echo "$repo.paths carves $new which the monolith does not build"
            continue
        fi

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
#
# The version check makes some thirty of these fetches back to back, and one of
# them coming back 429 or 5xx once is enough to fail a run that has nothing
# wrong with it. Answering that with a re-run is the thing this repo has
# already been bitten by: an intermittent failure that greens on the second try
# stops being read as a failure at all. So a fetch that did not answer is tried
# again, a handful of times, and a fetch that answered 404 is not — that is a
# real answer and retrying it would only make it slower.
read_pkgbuild() {
    local dir=$1 key=$2 url=$3 out=$4
    local attempts=${SHEDOS_FETCH_ATTEMPTS:-3} pause=${SHEDOS_FETCH_PAUSE:-2}
    local attempt=1 code=''
    if [[ -n $dir ]]; then
        [[ -f $dir/$key/PKGBUILD ]] || return 3
        cp -- "$dir/$key/PKGBUILD" "$out" 2>/dev/null || return 1
        return 0
    fi
    while :; do
        code=$(curl -sSL --max-time 60 -A "$USER_AGENT" -o "$out" -w '%{http_code}' "$url") \
            || code=''
        if [[ $code == 404 ]]; then
            return 3
        elif [[ $code == 2?? ]]; then
            return 0
        elif (( attempt >= attempts )); then
            return 1
        fi
        attempt=$((attempt + 1))
        sleep "$pause"
    done
}
