#!/usr/bin/env bash
# compare-package.sh <reference.pkg.tar.zst> <candidate.pkg.tar.zst> <expected-diffs>
#
# Ask whether two builds of the same package are the same package. The
# reference is the monolith's build, the candidate is the one the per-repo
# pipeline produced, and exit 0 means nothing separates them that was not
# expected and written down.
#
# Three tiers, all of them evaluated — a run reports everything it found, not
# the first thing that went wrong:
#
#   1. metadata  every .PKGINFO field, so a dependency or a provides cannot
#                move without saying so
#   2. manifest  the file lists, which have to be identical: a file that
#                appears or vanishes is what a packaging regression looks like
#   3. content   the bytes of every shared path, and the target of every
#                shared symlink
#
# Only content findings can be waved through, by naming them in the
# expected-diffs file, one per line:
#
#   content <path> — <reason>
#
# Metadata and manifest findings are deliberately not allowlistable. The whole
# point of the check is that the cutover cannot paper over a drift in what the
# package claims to be or what it carries.
#
# Every expectation that matched is printed, and one that matched nothing
# fails the run, so an allowlist cannot quietly outlive the difference it was
# written for.
set -euo pipefail

die() { printf 'compare: %s\n' "$*" >&2; exit 2; }

(( $# == 3 )) || die 'usage: compare-package.sh <reference> <candidate> <expected-diffs>'
ref=$1 cand=$2 expected_file=$3
for f in "$ref" "$cand" "$expected_file"; do
    [[ -f $f ]] || die "$f does not exist"
done

# builddate and packager say when and where a build ran, never what it built.
# size is the sum of the installed bytes, so it is not independent evidence:
# it moves if and only if some file's content moved, which the content tier
# reports against the path that actually changed. Comparing it would mean any
# package with an expected content difference could never pass, which would
# make the allowlist useless. It is printed as a note instead of ignored.
IGNORED_FIELDS=(builddate packager)
DERIVED_FIELDS=(size)

# .BUILDINFO records the build environment and .MTREE records timestamps, so
# both differ between any two machines by design.
META_MEMBERS=(.PKGINFO .BUILDINFO .MTREE)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

findings=()
finding() { findings+=("$1"); }

contains() {
    local needle=$1 item
    shift
    for item in "$@"; do
        [[ $item == "$needle" ]] && return 0
    done
    return 1
}

# --- tier 1: metadata -------------------------------------------------------

# Fields repeat — depend, provides, conflict, backup — so a field is a sorted
# list of values, not a scalar, and it is compared as one.
pkginfo_fields() {
    bsdtar -xOf "$1" .PKGINFO \
        | sed -e 's/[[:space:]]*$//' -e '/^#/d' -e '/^$/d' \
        | awk -F' = ' 'NF > 1 { print $1 "\t" substr($0, index($0, " = ") + 3) }' \
        | LC_ALL=C sort
}

pkginfo_fields "$ref"  > "$work/ref.fields"
pkginfo_fields "$cand" > "$work/cand.fields"

# One value per line, which is how they are compared: a value cannot contain a
# newline in a line-oriented format, so this is exact. Joining them into one
# string first would let ('a,b') and ('a' 'b') read as the same field.
values_of() { awk -F'\t' -v f="$2" '$1 == f { print $2 }' "$1"; }
oneline() { printf '%s' "$1" | paste -sd, -; }

fields=$(cut -f1 "$work/ref.fields" "$work/cand.fields" | LC_ALL=C sort -u)
for field in $fields; do
    contains "$field" "${IGNORED_FIELDS[@]}" && continue
    ref_values=$(values_of "$work/ref.fields" "$field")
    cand_values=$(values_of "$work/cand.fields" "$field")
    [[ $ref_values != "$cand_values" ]] || continue
    if contains "$field" "${DERIVED_FIELDS[@]}"; then
        printf 'note: %s %s != %s (derived from the installed bytes; see the content findings)\n' \
            "$field" "$(oneline "$ref_values")" "$(oneline "$cand_values")"
        continue
    fi
    finding "pkginfo $field: $(oneline "$ref_values") != $(oneline "$cand_values")"
done

# --- tier 2: manifest -------------------------------------------------------

manifest_of() {
    bsdtar -tf "$1" | sed -e 's|^\./||' -e 's|/$||' -e '/^$/d' \
        | grep -vxF "$(printf '%s\n' "${META_MEMBERS[@]}")" \
        | LC_ALL=C sort -u
}

manifest_of "$ref"  > "$work/ref.manifest"
manifest_of "$cand" > "$work/cand.manifest"

while IFS= read -r path; do
    [[ -n $path ]] && finding "manifest only-in-ref: $path"
done < <(LC_ALL=C comm -23 "$work/ref.manifest" "$work/cand.manifest")

while IFS= read -r path; do
    [[ -n $path ]] && finding "manifest only-in-cand: $path"
done < <(LC_ALL=C comm -13 "$work/ref.manifest" "$work/cand.manifest")

# --- tier 3: content --------------------------------------------------------

# Extracting is what makes a symlink comparable: `bsdtar -xO` on one yields no
# bytes at all, so two symlinks pointing at different files would hash the
# same and pass.
for side in ref cand; do
    mkdir -p "$work/$side.tree"
    bsdtar -xf "${!side}" -C "$work/$side.tree"
done

# What the path is, and what it is made of. A directory has nothing to compare
# beyond its presence, which the manifest tier already settled.
fingerprint() {
    local file=$1
    if [[ -L $file ]]; then
        printf 'symlink %s' "$(readlink "$file")"
    elif [[ -d $file ]]; then
        printf 'directory'
    elif [[ -f $file ]]; then
        printf 'file %s' "$(sha256sum < "$file" | cut -d' ' -f1)"
    else
        printf 'other'
    fi
}

differing=()
while IFS= read -r path; do
    [[ -n $path ]] || continue
    [[ -d $work/ref.tree/$path && ! -L $work/ref.tree/$path ]] && continue
    if [[ $(fingerprint "$work/ref.tree/$path") \
       != $(fingerprint "$work/cand.tree/$path") ]]; then
        differing+=("$path")
    fi
done < <(LC_ALL=C comm -12 "$work/ref.manifest" "$work/cand.manifest")

# --- the expected-diffs file ------------------------------------------------

expected_paths=()
expected_reasons=()
lineno=0
while IFS= read -r line || [[ -n $line ]]; do
    lineno=$((lineno + 1))
    line=${line#"${line%%[![:space:]]*}"}
    [[ -n $line && $line != '#'* ]] || continue
    # The directive is checked before the shape of the rest, so naming a
    # manifest or metadata finding is answered with why it can never be
    # expected rather than with a complaint about punctuation.
    kind=${line%%[[:space:]]*}
    if [[ $kind != content ]]; then
        die "line $lineno of $expected_file names '$kind': only 'content' differences can be expected"
    fi
    if [[ ! $line =~ ^content[[:space:]]+([^[:space:]]+)([[:space:]]+—[[:space:]]*(.*))?$ ]]; then
        die "line $lineno of $expected_file is not 'content <path> — <reason>': $line"
    fi
    expected_paths+=("${BASH_REMATCH[1]}")
    expected_reasons+=("${BASH_REMATCH[3]:-no reason given}")
done < "$expected_file"

matched=0
for path in "${differing[@]}"; do
    if contains "$path" "${expected_paths[@]}"; then
        matched=$((matched + 1))
    else
        finding "content: $path"
    fi
done

# Every expectation is either credited out loud or called out as stale, so an
# allowlist entry that has stopped describing anything cannot sit unnoticed.
for i in "${!expected_paths[@]}"; do
    path=${expected_paths[i]}
    if contains "$path" "${differing[@]}"; then
        printf 'expected: %s (%s)\n' "$path" "${expected_reasons[i]}"
    else
        finding "stale expectation: $path"
    fi
done

# --- the verdict ------------------------------------------------------------

if (( ${#findings[@]} > 0 )); then
    printf '%s\n' "${findings[@]}"
fi

compared=$(wc -l < "$work/ref.manifest")
if (( ${#findings[@]} == 0 )); then
    printf 'equivalent — %s paths compared, %d expected difference(s)\n' \
        "$compared" "$matched"
    exit 0
fi
printf 'NOT equivalent — %d unexplained difference(s) across %s paths\n' \
    "${#findings[@]}" "$compared"
exit 1
