#!/usr/bin/env bash
# verify-enumeration.sh repo <maps-file> <monolith> <commit> <repo-dir> <ref> [<expected-diffs>]
# verify-enumeration.sh set  <maps-dir>  <monolith> <commit> <origin> <name>=<dir>[#<ref>]...
#
# Every enumeration acceptance cites this tool.
#
# `repo` walks a carved repository against the monolith it came out of. It
# reads the repository's maps file, maps each carved path back to the monolith
# path it was taken from, and sorts the tree into three: identical to the
# monolith, transformed, and holding no monolith counterpart at all. Given the
# repository's expected-diffs file it then reconciles the transformed set
# against it in both directions — nothing different that is not written down,
# nothing written down that is not different — and re-derives every pin.
#
# `set` asks the question no single repository can answer. A package that split
# across several repositories has files that LEFT it, and a walk of any one
# side cannot tell a file that moved to a sibling from a file that was dropped.
# Given the monolith directory that was split and the repositories the split
# went to, this holds every file under that directory against the maps that
# claim it and the trees that are supposed to hold it. A file no map claims is
# a file the split deleted in silence, and that is what it exists to catch. The
# members are whichever maps take from the directory rather than whichever were
# named, so a repository left off the command line is refused by name instead
# of turning its share of the split into a pile of unclaimed files.
#
# Both modes read the monolith with `git ls-tree` and never check it out, and
# both compare against the tree at the named commit rather than the history: a
# carved tree holds what the monolith tree holds. An `except` naming a path
# only the history has is noted rather than refused, because carve.sh reads the
# history and is the one that refuses.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=tools/lib-carve-maps.sh
source "$HERE/lib-carve-maps.sh"

die() { printf 'verify-enumeration: %s\n' "$*" >&2; exit 2; }

notes=()
findings=()
note()    { notes+=("note: $*"); }
finding() { findings+=("$*"); }

# --- reading the trees ------------------------------------------------------

declare -A MODE_OF=() OID_OF=()

# One tree into MODE_OF and OID_OF, every path under the given prefix so
# several trees can sit in the two arrays at once.
read_tree() {
    local repo=$1 rev=$2 prefix=$3 line meta path mode type oid
    [[ -d $repo ]] || die "$repo is not a directory"
    while IFS= read -r line; do
        meta=${line%%$'\t'*}
        path=${line#*$'\t'}
        read -r mode type oid <<<"$meta"
        [[ $type == blob ]] || continue
        MODE_OF[$prefix$path]=$mode
        OID_OF[$prefix$path]=$oid
    done < <(git -C "$repo" ls-tree -r "$rev" 2>/dev/null)
}

paths_under() {
    local prefix=$1 path
    for path in "${!OID_OF[@]}"; do
        [[ $path == "$prefix"* ]] && printf '%s\n' "${path#"$prefix"}"
    done | LC_ALL=C sort
}

# Every monolith path a maps file selects, written to $1 as "<monolith
# path>\t<carved path>". The excepts are subtracted first and in the monolith's
# own path names, the way carve.sh subtracts them, so a rename beside one still
# replays from the path the monolith used.
selection_of() {
    local out=$1 map=$2 mono_paths=$3 path hits pair kept

    read_map "$map" || die "$MAP_ERROR"

    kept=$mono_paths
    for path in "${MAP_EXCEPTS[@]}"; do
        hits=$(map_move "$path" "$path" <<<"$mono_paths")
        if [[ -z $hits ]]; then
            note "$map excepts $path, which the tree at this commit does not have"
            continue
        fi
        kept=$(LC_ALL=C comm -23 <(printf '%s\n' "$kept") \
            <(printf '%s\n' "$hits" | LC_ALL=C sort -u))
    done

    local selected
    selected=$(
        for pair in "${MAP_PAIRS[@]}"; do
            map_move "${pair%%$'\t'*}" "${pair%%$'\t'*}" <<<"$kept"
        done | LC_ALL=C sort -u
    )
    map_place "$selected" | LC_ALL=C sort -u > "$out"
}

# Where the excepted paths would have landed had they not been subtracted, so a
# subtraction that did not happen can be looked for by name. The selection
# cannot show this one: an excepted path is selected by the very directive it
# is being taken out of.
except_destinations() {
    local map=$1 mono_paths=$2 path excepted

    read_map "$map" || die "$MAP_ERROR"
    excepted=$(
        for path in "${MAP_EXCEPTS[@]}"; do
            map_move "$path" "$path" <<<"$mono_paths"
        done | LC_ALL=C sort -u
    )
    [[ -n $excepted ]] || return 0
    map_place "$excepted" | cut -f2 | LC_ALL=C sort -u
}

# --- the expected-diffs file ------------------------------------------------

expected_paths=()
expected_pins=()
expected_reasons=()

read_expectations() {
    local file=$1 lineno=0 line kind
    while IFS= read -r line || [[ -n $line ]]; do
        lineno=$((lineno + 1))
        line=${line#"${line%%[![:space:]]*}"}
        [[ -n $line && $line != '#'* ]] || continue
        kind=${line%%[[:space:]]*}
        if [[ $kind != content ]]; then
            die "line $lineno of $file names '$kind': only 'content' differences can be expected"
        fi
        # A 64-character pin is a sha256 of installed bytes, which is the shape
        # an enumeration of a built package takes. This walks a carved tree and
        # pins git blobs, and neither file can answer the other's question.
        if [[ $line =~ [0-9a-f]{64}\.\.[0-9a-f]{64} ]]; then
            die "line $lineno of $file pins a built package's bytes: this walks a carved tree"
        fi
        if [[ ! $line =~ ^content[[:space:]]+([^[:space:]]+)([[:space:]]+([0-9a-f]{40})\.\.([0-9a-f]{40}))?[[:space:]]+—[[:space:]]*(.+)$ ]]; then
            die "line $lineno of $file is not 'content <path> [<mono>..<carved>] — <reason>': $line"
        fi
        expected_paths+=("${BASH_REMATCH[1]}")
        expected_pins+=("${BASH_REMATCH[3]:+${BASH_REMATCH[3]}..${BASH_REMATCH[4]}}")
        expected_reasons+=("${BASH_REMATCH[5]}")
    done < "$file"
}

# An entry explains a path only if it names it, the path really differs, and —
# when pinned — the two sides still hash to exactly what it was written for.
entry_matches() {
    local i=$1 path=$2 src
    [[ ${expected_paths[i]} == "$path" ]] || return 1
    [[ -n ${differs[$path]:-} ]] || return 1
    [[ -n ${expected_pins[i]} ]] || return 0
    src=${source_of[$path]}
    [[ ${expected_pins[i]} == "${OID_OF[M:$src]}..${OID_OF[C:$path]}" ]]
}

# Nothing different that is not written down, nothing written down that is not
# different. Every expectation is either credited or called out as stale, so an
# entry that has stopped describing anything cannot sit unnoticed.
reconcile() {
    local file=$1 path i explained matched=0

    read_expectations "$file"

    for path in "${!differs[@]}"; do
        explained=
        for i in "${!expected_paths[@]}"; do
            entry_matches "$i" "$path" && { explained=yes; break; }
        done
        if [[ -n $explained ]]; then
            matched=$((matched + 1))
        else
            finding "transformed and not written down: $path"
        fi
    done

    for i in "${!expected_paths[@]}"; do
        path=${expected_paths[i]}
        if entry_matches "$i" "$path"; then
            [[ -n ${expected_pins[i]} ]] \
                || note "unpinned expectation $path — it will forgive any future change to this path"
        else
            finding "written down and not a difference: $path"
        fi
    done

    printf '  %s: claimed %d, transformed %d, reconciled %d\n' \
        "$file" "${#expected_paths[@]}" "${#differs[@]}" "$matched"
}

# --- repo mode --------------------------------------------------------------

declare -A source_of=() differs=()

verify_repo() {
    local map=$1 mono=$2 commit=$3 repo=$4 ref=$5 expected_file=${6:-}
    local mono_paths carved src dst path
    local pkg_same=0 pkg_diff=0 test_same=0 test_diff=0 orphan=0
    local -A held=()
    local sel=$WORK/selection

    read_tree "$mono" "$commit" 'M:'
    read_tree "$repo" "$ref" 'C:'
    mono_paths=$(paths_under 'M:')
    carved=$(paths_under 'C:')
    [[ -n $mono_paths ]] || die "$mono has no tree at $commit"
    [[ -n $carved ]] || die "$repo has no tree at $ref"

    selection_of "$sel" "$map" "$mono_paths"
    while IFS=$'\t' read -r src dst; do
        [[ -n $dst ]] || continue
        [[ -z ${source_of[$dst]:-} ]] \
            || finding "two monolith paths land on $dst: ${source_of[$dst]} and $src"
        source_of[$dst]=$src
    done < "$sel"

    while IFS= read -r path; do
        [[ -n $path ]] || continue
        src=${source_of[$path]:-}
        if [[ -z $src ]]; then
            orphan=$((orphan + 1))
            continue
        fi
        held[$path]=yes
        if [[ ${OID_OF[M:$src]} == "${OID_OF[C:$path]}" ]]; then
            if [[ $path == test/* ]]; then test_same=$((test_same + 1))
            else pkg_same=$((pkg_same + 1)); fi
        else
            differs[$path]=yes
            if [[ $path == test/* ]]; then test_diff=$((test_diff + 1))
            else pkg_diff=$((pkg_diff + 1)); fi
        fi
        [[ ${MODE_OF[M:$src]} == "${MODE_OF[C:$path]}" ]] \
            || finding "mode $path ${MODE_OF[M:$src]} -> ${MODE_OF[C:$path]}"
    done <<<"$carved"

    for path in "${!source_of[@]}"; do
        [[ -n ${held[$path]:-} ]] \
            || finding "selected and absent from the tree: $path (${source_of[$path]})"
    done

    while IFS= read -r path; do
        [[ -n $path && -n ${OID_OF[C:$path]:-} ]] \
            && finding "excepted and present in the tree: $path"
    done <<<"$(except_destinations "$map" "$mono_paths")"

    printf '%s at %s against the monolith at %s\n' \
        "$(basename "$repo")" "$(git -C "$repo" rev-parse --short "$ref")" \
        "$(git -C "$mono" rev-parse --short "$commit")"
    printf '  package %d/%d, test %d/%d, no counterpart %d\n' \
        "$pkg_same" "$pkg_diff" "$test_same" "$test_diff" "$orphan"

    [[ -z $expected_file ]] || reconcile "$expected_file"
    report
}

# --- set mode ---------------------------------------------------------------

verify_set() {
    local maps_dir=$1 mono=$2 commit=$3 origin=$4
    shift 4
    local spec name file src dst path member claimants
    local mono_paths origin_paths missing=() members=()
    local -A repo_dir=() repo_ref=() claimed_by=() lands_at=()
    local once=0 none=0 many=0 absent=0
    local sel=$WORK/selection

    for spec in "$@"; do
        [[ $spec == *=* ]] || die "'$spec' is not <name>=<dir>[#<ref>]"
        name=${spec%%=*}
        spec=${spec#*=}
        repo_dir[$name]=${spec%%#*}
        repo_ref[$name]=HEAD
        [[ $spec == *#* ]] && repo_ref[$name]=${spec#*#}
        members+=("$name")
    done

    read_tree "$mono" "$commit" 'M:'
    mono_paths=$(paths_under 'M:')
    [[ -n $mono_paths ]] || die "$mono has no tree at $commit"
    origin=${origin%/}
    origin_paths=$(map_move "$origin" "$origin" <<<"$mono_paths")
    [[ -n $origin_paths ]] || die "$mono has nothing under $origin at $commit"

    # Every map is expanded against the whole monolith rather than against the
    # origin alone, so an `except` reaching outside it still finds what it
    # names instead of reading as a directive that matched nothing.
    for file in "$maps_dir"/*.paths; do
        name=$(basename "$file" .paths)
        selection_of "$sel" "$file" "$mono_paths"
        awk -v under="$origin/" 'index($0, under) == 1' "$sel" > "$sel.origin"
        mv "$sel.origin" "$sel"
        [[ -s $sel ]] || continue
        if [[ -z ${repo_dir[$name]:-} ]]; then
            missing+=("$name")
            continue
        fi
        while IFS=$'\t' read -r src dst; do
            [[ -n $src ]] || continue
            claimed_by[$src]+=" $name"
            lands_at[$src$'\t'$name]=$dst
        done < "$sel"
    done
    (( ${#missing[@]} == 0 )) \
        || die "these maps take from $origin and no repository was given for them: ${missing[*]}"

    for name in "${members[@]}"; do
        read_tree "${repo_dir[$name]}" "${repo_ref[$name]}" "$name:"
    done

    while IFS= read -r path; do
        [[ -n $path ]] || continue
        claimants=${claimed_by[$path]:-}
        if [[ -z $claimants ]]; then
            none=$((none + 1))
            finding "no map claims $path"
            continue
        fi
        if [[ $claimants == *' '*' '* ]]; then
            many=$((many + 1))
            finding "$path is claimed by${claimants}"
        else
            once=$((once + 1))
        fi
        for member in $claimants; do
            dst=${lands_at[$path$'\t'$member]}
            [[ -n ${OID_OF[$member:$dst]:-} ]] && continue
            absent=$((absent + 1))
            finding "$path went to $member and $member does not hold $dst"
        done
    done <<<"$origin_paths"

    printf 'the split of %s at %s\n' \
        "$origin" "$(git -C "$mono" rev-parse --short "$commit")"
    printf '  %d files under %s, taken by %s\n' \
        "$(grep -c . <<<"$origin_paths")" "$origin" \
        "$(printf '%s\n' "${members[@]}" | LC_ALL=C sort | paste -sd' ')"
    printf '  claimed once %d, claimed by none %d, claimed by several %d, claimed and absent %d\n' \
        "$once" "$none" "$many" "$absent"
    report
}

# --- the verdict ------------------------------------------------------------

report() {
    local line
    for line in ${notes[@]+"${notes[@]}"}; do printf '  %s\n' "$line"; done
    for line in ${findings[@]+"${findings[@]}"}; do printf '  %s\n' "$line"; done
    if (( ${#findings[@]} == 0 )); then
        printf 'reconciled — nothing unaccounted for\n'
        exit 0
    fi
    printf 'NOT reconciled — %d unaccounted for\n' "${#findings[@]}"
    exit 1
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mode=${1:-}
shift || true
case $mode in
    repo)
        (( $# == 5 || $# == 6 )) || die \
            'usage: verify-enumeration.sh repo <maps-file> <monolith> <commit> <repo-dir> <ref> [<expected-diffs>]'
        verify_repo "$@"
        ;;
    set)
        (( $# >= 5 )) || die \
            'usage: verify-enumeration.sh set <maps-dir> <monolith> <commit> <origin> <name>=<dir>[#<ref>]...'
        verify_set "$@"
        ;;
    *) die 'usage: verify-enumeration.sh repo|set ...' ;;
esac
