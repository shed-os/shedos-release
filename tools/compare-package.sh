#!/usr/bin/env bash
# compare-package.sh <reference.pkg.tar.zst> <candidate.pkg.tar.zst> <expected-diffs>
#
# Ask whether two builds of the same package are the same package. The
# reference is the monolith's build, the candidate is the one the per-repo
# pipeline produced, and exit 0 means nothing separates them that was not
# expected and written down.
#
# Four tiers, all of them evaluated — a run reports everything it found, not
# the first thing that went wrong:
#
#   1. metadata  every .PKGINFO field, so a dependency or a provides cannot
#                move without saying so
#   2. manifest  the file lists, which have to be identical: a file that
#                appears or vanishes is what a packaging regression looks like
#   3. content   the bytes of every shared path, the target of every symlink
#                and the shape of everything else
#   4. mtree     the mode, owner and type .MTREE recorded at build time, which
#                is the only trustworthy record of them
#
# Only content findings can be waved through, by naming them in the
# expected-diffs file, one per line, in either form:
#
#   content <path> — <reason>
#   content <path> <ref-sha256>..<cand-sha256> — <reason>
#
# The second pins the entry to one exact difference: if either side's bytes
# change again the entry stops matching and the new difference is unexplained.
# The first still works, and says so, because an unpinned entry keeps
# forgiving that path whatever happens to it.
#
# Metadata, manifest and mtree findings are not allowlistable.
# The whole point of the check is that the cutover cannot paper over a drift
# in what the package claims to be, what it carries, or how it is installed.
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
IGNORED_FIELDS=(builddate packager)

# .BUILDINFO records the build environment and .MTREE records timestamps, so
# neither can be compared whole. .MTREE is read again by the fourth tier for
# the columns that are not timestamps.
META_MEMBERS=(.PKGINFO .BUILDINFO .MTREE)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

findings=()
notes=()
credits=()
finding() { findings+=("$1"); }
note()    { notes+=("note: $1"); }

contains() {
    local needle=$1 item
    shift
    for item in "$@"; do
        [[ $item == "$needle" ]] && return 0
    done
    return 1
}

# --- tier 1: metadata -------------------------------------------------------

# Fields repeat — depend, provides, conflict, backup — so a field is a list of
# values, not a scalar. One value per line, which is how they are compared: a
# value cannot contain a newline in a line-oriented format, so this is exact.
# Joining them into one string first would let ('a,b') and ('a' 'b') read as
# the same field.
pkginfo_fields() {
    bsdtar -xOf "$1" .PKGINFO \
        | sed -e 's/[[:space:]]*$//' -e '/^#/d' -e '/^$/d' \
        | awk -F' = ' 'NF > 1 { print $1 "\t" substr($0, index($0, " = ") + 3) }' \
        | LC_ALL=C sort
}

values_of() { awk -F'\t' -v f="$2" '$1 == f { print $2 }' "$1"; }
oneline() { printf '%s' "$1" | paste -sd, -; }

pkginfo_fields "$ref"  > "$work/ref.fields"
pkginfo_fields "$cand" > "$work/cand.fields"

# size is the sum of the installed bytes, so it is not independent evidence —
# but it is not free to ignore either, because makepkg counts a hardlinked
# file once. Two packages can carry identical manifests and identical bytes
# and still disagree on size, which is a real difference in what gets
# installed. It is settled after the content tier, against what that tier
# found.
ref_size=$(values_of "$work/ref.fields" size)
cand_size=$(values_of "$work/cand.fields" size)

fields=$(cut -f1 "$work/ref.fields" "$work/cand.fields" | LC_ALL=C sort -u)
for field in $fields; do
    contains "$field" "${IGNORED_FIELDS[@]}" && continue
    [[ $field == size ]] && continue
    ref_values=$(values_of "$work/ref.fields" "$field")
    cand_values=$(values_of "$work/cand.fields" "$field")
    [[ $ref_values != "$cand_values" ]] || continue
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

# What the path is, and what it is made of. Both sides go through this, so a
# path that is a directory on one side and a symlink on the other is a
# difference rather than something to skip: deciding by the reference alone
# would let an empty directory turn into a symlink silently, since the two
# normalise to the same manifest entry.
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

# The bytes a path contributes to the installed size, and what an expectation
# pins against. Only regular files have either.
sha_of() {
    local file=$1
    if [[ -f $file && ! -L $file ]]; then sha256sum < "$file" | cut -d' ' -f1
    else printf '%s' -
    fi
}
len_of() {
    local file=$1
    if [[ -f $file && ! -L $file ]]; then stat -c %s "$file"
    else printf 0
    fi
}

differing=()
diff_ref_sha=()
diff_cand_sha=()
while IFS= read -r path; do
    [[ -n $path ]] || continue
    if [[ $(fingerprint "$work/ref.tree/$path") \
       != $(fingerprint "$work/cand.tree/$path") ]]; then
        differing+=("$path")
        diff_ref_sha+=("$(sha_of "$work/ref.tree/$path")")
        diff_cand_sha+=("$(sha_of "$work/cand.tree/$path")")
    fi
done < <(LC_ALL=C comm -12 "$work/ref.manifest" "$work/cand.manifest")

# --- size, reconciled against what the content tier found -------------------

if [[ -z $ref_size || -z $cand_size ]]; then
    [[ $ref_size == "$cand_size" ]] \
        || finding "pkginfo size: $(oneline "$ref_size") != $(oneline "$cand_size")"
else
    observed=$((ref_size - cand_size))
    predicted=0
    for path in "${differing[@]}"; do
        predicted=$((predicted + $(len_of "$work/ref.tree/$path") \
                               - $(len_of "$work/cand.tree/$path")))
    done
    if (( observed == predicted )); then
        (( observed == 0 )) || note \
            "size $ref_size != $cand_size, accounted for by the content findings"
    else
        # Nothing in the content tier explains the move. A hardlink becoming a
        # copy does exactly this: same manifest, same bytes, more installed.
        finding "pkginfo size: observed $observed != predicted $predicted from the content findings"
    fi
fi

# --- tier 4: mode, owner and type -------------------------------------------

# Read from .MTREE rather than from the extracted trees: the extraction runs
# unprivileged, so it cannot be trusted to reproduce a setuid bit — which is
# the thing most worth catching. Timestamps are why .MTREE cannot be compared
# whole, so they are the one column left out.
#
# A /set line changes the defaults for the lines that follow and merges into
# whatever is already set, so the defaults have to be carried down the file.
mtree_attrs() {
    bsdtar -xOf "$1" .MTREE | zcat | awk '
        /^#/ || /^$/ { next }
        $1 == ".." { next }
        $1 == "/set" || $1 == "/unset" {
            for (i = 2; i <= NF; i++) {
                if ($1 == "/unset") { delete def[$i]; continue }
                p = index($i, "="); def[substr($i, 1, p - 1)] = substr($i, p + 1)
            }
            next
        }
        {
            path = $1; sub(/^\.\//, "", path)
            for (k in def) val[k] = def[k]
            for (i = 2; i <= NF; i++) {
                p = index($i, "="); val[substr($i, 1, p - 1)] = substr($i, p + 1)
            }
            printf "%s\ttype=%s\tmode=%s\tuid=%s\tgid=%s\n", path,
                ("type" in val) ? val["type"] : "-",
                ("mode" in val) ? val["mode"] : "-",
                ("uid" in val) ? val["uid"] : "-",
                ("gid" in val) ? val["gid"] : "-"
            delete val
        }' | LC_ALL=C sort -t$'\t' -k1,1
}

for side in ref cand; do
    if ! mtree_attrs "${!side}" > "$work/$side.mtree" || [[ ! -s $work/$side.mtree ]]; then
        finding "mtree: the $side package has no readable .MTREE"
        : > "$work/$side.mtree"
    fi
done

# Only paths both sides carry — the manifest tier already answered presence.
while IFS=$'\t' read -r path r_type r_mode r_uid r_gid c_type c_mode c_uid c_gid; do
    [[ -n $path ]] || continue
    contains "$path" "${META_MEMBERS[@]}" && continue
    [[ $r_type == "$c_type" ]] || finding "mtree $path: type ${r_type#type=} != ${c_type#type=}"
    [[ $r_mode == "$c_mode" ]] || finding "mtree $path: mode ${r_mode#mode=} != ${c_mode#mode=}"
    [[ $r_uid  == "$c_uid"  ]] || finding "mtree $path: uid ${r_uid#uid=} != ${c_uid#uid=}"
    [[ $r_gid  == "$c_gid"  ]] || finding "mtree $path: gid ${r_gid#gid=} != ${c_gid#gid=}"
done < <(LC_ALL=C join -t$'\t' "$work/ref.mtree" "$work/cand.mtree")

# --- the expected-diffs file ------------------------------------------------

expected_paths=()
expected_pins=()
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
    if [[ ! $line =~ ^content[[:space:]]+([^[:space:]]+)([[:space:]]+([0-9a-f]{64})\.\.([0-9a-f]{64}))?[[:space:]]+—[[:space:]]*(.+)$ ]]; then
        die "line $lineno of $expected_file is not 'content <path> [<ref-sha>..<cand-sha>] — <reason>': $line"
    fi
    expected_paths+=("${BASH_REMATCH[1]}")
    expected_pins+=("${BASH_REMATCH[3]:+${BASH_REMATCH[3]}..${BASH_REMATCH[4]}}")
    expected_reasons+=("${BASH_REMATCH[5]}")
done < "$expected_file"

# An entry explains a path only if it names it and, when pinned, the two sides
# still hash to exactly what it was written for.
entry_matches() {
    local i=$1 path=$2 j
    [[ ${expected_paths[i]} == "$path" ]] || return 1
    for j in "${!differing[@]}"; do
        if [[ ${differing[j]} == "$path" ]]; then
            [[ -n ${expected_pins[i]} ]] || return 0
            [[ ${expected_pins[i]} == "${diff_ref_sha[j]}..${diff_cand_sha[j]}" ]] \
                && return 0
            return 1
        fi
    done
    # The path is not differing at all, so there is nothing here to expect.
    return 1
}

matched=0
for path in "${differing[@]}"; do
    explained=
    for i in "${!expected_paths[@]}"; do
        entry_matches "$i" "$path" && { explained=yes; break; }
    done
    if [[ -n $explained ]]; then
        matched=$((matched + 1))
    else
        finding "content: $path"
    fi
done

# Every expectation is either credited out loud or called out as stale, so an
# allowlist entry that has stopped describing anything cannot sit unnoticed.
for i in "${!expected_paths[@]}"; do
    path=${expected_paths[i]}
    if entry_matches "$i" "$path"; then
        credits+=("expected: $path (${expected_reasons[i]})")
        [[ -n ${expected_pins[i]} ]] \
            || note "unpinned expectation $path — it will forgive any future change to this path"
    else
        finding "stale expectation: $path"
    fi
done

# --- the verdict ------------------------------------------------------------

for line in ${notes[@]+"${notes[@]}"} ${credits[@]+"${credits[@]}"} \
            ${findings[@]+"${findings[@]}"}; do
    printf '%s\n' "$line"
done

compared=$(wc -l < "$work/ref.manifest")
if (( ${#findings[@]} == 0 )); then
    printf 'equivalent — %s paths compared, %d expected difference(s)\n' \
        "$compared" "$matched"
    exit 0
fi
printf 'NOT equivalent — %d unexplained difference(s) across %s paths\n' \
    "${#findings[@]}" "$compared"
exit 1
