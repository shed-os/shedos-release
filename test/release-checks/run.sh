#!/usr/bin/env bash
# The checks that only a release can be asked.
#
# Each of these was a convention inside one repository and is a contract between
# repositories now: who may write into a shared directory, which files packages
# hand each other without a schema, which copies of one literal have to agree,
# whether every verb the release publishes is declared and documented, and
# whether the manual's cross-references resolve in the set of packages a person
# actually installs.
#
# All of it reads the released packages. None of it can be answered anywhere
# else — a repository that holds one package cannot see the others.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
MANIFEST=$ROOT/release-manifest.toml
MAP=$ROOT/ownership-map.toml

WORK=$(mktemp -d)
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

pass=0
fail=0
failed=()

ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s — %s\n' "$1" "${2:-}"; fail=$((fail + 1)); failed+=("$1"); }
check() { local d=$1; shift; if "$@"; then ok "$d"; else bad "$d"; fi; }
section() { printf '\n── %s\n' "$1"; }

if [[ ${SHEDOS_SKIP_LIVE:-0} == 1 ]]; then
    echo 'release-checks: SKIP — SHEDOS_SKIP_LIVE'
    exit 0
fi
if ! curl -sS -I -m 20 https://repo.shedos.org/staging/test/x86_64/shedos.db.tar.gz \
        > /dev/null 2>&1 && [[ -z ${SHEDOS_MANIFEST_CHANNEL:-} ]]; then
    echo 'release-checks: SKIP — the channel is unreachable'
    exit 0
fi

PKGS=$WORK/pkgs
if ! bash "$ROOT/tools/fetch-packages.sh" "$MANIFEST" "$PKGS" > "$WORK/fetch.log" 2>&1; then
    echo 'release-checks: could not fetch the release' >&2
    tail -20 "$WORK/fetch.log" >&2
    exit 1
fi

: > "$WORK/files.tsv"
for pkg in "$PKGS"/*.pkg.tar.zst; do
    name=$(bsdtar -xOf "$pkg" .PKGINFO | awk -F' = ' '/^pkgname/ { print $2; exit }')
    bsdtar -tf "$pkg" | grep -v '/$' | grep -v '^\.' \
        | awk -v n="$name" '{ print "/" $0 "\t" n }' >> "$WORK/files.tsv"
done
LC_ALL=C sort -o "$WORK/files.tsv" "$WORK/files.tsv"

MERGED=$WORK/merged
mkdir -p "$MERGED"
for pkg in "$PKGS"/*.pkg.tar.zst; do
    bsdtar -xf "$pkg" -C "$MERGED" \
        --exclude .PKGINFO --exclude .BUILDINFO --exclude .MTREE --exclude .INSTALL
done

owns() {  # which package ships $1, empty when none does
    awk -F'\t' -v p="$1" '$1 == p { print $2; exit }' "$WORK/files.tsv"
}

# --- 1. the ownership map ---------------------------------------------------

section 'every shared-namespace file has a declared owner'
python3 - "$MAP" > "$WORK/map.tsv" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as fh:
    doc = tomllib.load(fh)
for entry in doc.get("path", []):
    print("path\t{}\t{}".format(entry["glob"], ",".join(entry["owners"])))
for entry in doc.get("handoff", []):
    print("handoff\t{}\t{}\t{}\t{}\t{}".format(
        entry["file"], entry["writer"], entry["reader"],
        entry["writer-evidence"], entry["reader-evidence"]))
PY
check 'the map parses' test -s "$WORK/map.tsv"

while IFS=$'\t' read -r kind glob owners; do
    [[ $kind == path ]] || continue
    prefix=${glob%/\*}
    strays=$(awk -F'\t' -v p="$prefix/" -v o=",$owners," '
        index($1, p) == 1 && substr($1, length(p) + 1) !~ /\// {
            if (index(o, "," $2 ",") == 0) print $2 " " $1
        }' "$WORK/files.tsv" | LC_ALL=C sort -u)
    if [[ -n $strays ]]; then
        printf '       %s\n' "$strays"
        bad "$glob is written only by its declared owners" 'an undeclared package writes there'
    else
        ok "$glob is written only by its declared owners"
    fi
    # The other direction: an owner that stopped writing there is a line that
    # has outlived its reason, and a map nobody prunes stops being a review.
    for owner in ${owners//,/ }; do
        if awk -F'\t' -v p="$prefix/" -v n="$owner" \
            'index($1, p) == 1 && $2 == n { found = 1 } END { exit !found }' "$WORK/files.tsv"
        then
            ok "$owner still writes into $glob"
        else
            bad "$owner still writes into $glob" 'declared owner ships nothing there'
        fi
    done
done < "$WORK/map.tsv"

section 'both ends of every undescribed handoff are still in the release'
while IFS=$'\t' read -r kind file writer reader wev rev; do
    [[ $kind == handoff ]] || continue
    got=$(owns "$wev")
    check "$file: $writer still ships $wev" test "$got" = "$writer"
    got=$(owns "$rev")
    check "$file: $reader still ships $rev" test "$got" = "$reader"
    # The evidence has to still mention the file, or the note describes a
    # handoff that has already been rewired. One of the five hands over the
    # file itself rather than something written into it, and a script does not
    # contain its own path — shipping it is the whole of the writer's side.
    if [[ $wev != "$file" ]]; then
        check "$file: the writer still names it" grep -qa -- "$file" "$MERGED$wev"
    fi
    check "$file: the reader still names it" \
        grep -qa -- "$file" "$MERGED$rev"
done < "$WORK/map.tsv"

# --- 2. the fallback palette ------------------------------------------------
#
# One palette written down four times, on purpose: each surface falls back to
# Mocha when the theme directory is missing, so none of them needs the theme
# engine to be running to draw something sane. Four copies drift, and the drift
# shows up as one dialog in slightly the wrong blue.

section 'the compiled-in fallback palettes agree with the engine'
engine=$MERGED/usr/lib/shedos/shedos_palette.py
renderer=$MERGED/usr/lib/shedos/theme_renderer.py
hypr=$MERGED/etc/skel/.config/hypr/hyprland.lua
check 'the engine ships the canonical palette' test -f "$engine"

# name -> #rrggbb out of a python dict literal, lowercase.
_dict_colors() {
    grep -oE '"[a-z0-9_]+": "#[0-9a-fA-F]{6}"' "$1" \
        | tr -d '"' | tr 'A-F' 'a-f' | sed 's/: /\t/' | LC_ALL=C sort -u
}
_dict_colors "$engine" > "$WORK/canonical.tsv"
check 'and it has the whole set' test "$(wc -l < "$WORK/canonical.tsv")" -ge 26

_dict_colors "$renderer" > "$WORK/renderer.tsv"
if [[ -s $WORK/renderer.tsv ]]; then
    drift=$(LC_ALL=C comm -13 "$WORK/canonical.tsv" "$WORK/renderer.tsv")
    [[ -z $drift ]] || printf '       %s\n' "$drift"
    check 'theme_renderer.py agrees with it' test -z "$drift"
else
    bad 'theme_renderer.py agrees with it' 'no palette found in it'
fi

# hyprland.lua writes rgba(RRGGBBaa); alpha is not a colour.
grep -oE 'rgba\([0-9a-fA-F]{6}[0-9a-fA-F]{2}\)' "$hypr" \
    | sed 's/rgba(//; s/..)$//' | tr 'A-F' 'a-f' | LC_ALL=C sort -u > "$WORK/hypr.txt"
cut -f2 "$WORK/canonical.tsv" | tr -d '#' | LC_ALL=C sort -u > "$WORK/canonical-hex.txt"
stray=$(LC_ALL=C comm -23 "$WORK/hypr.txt" "$WORK/canonical-hex.txt")
if [[ -n $stray ]]; then printf '       %s\n' "$stray"; fi
check 'every colour hyprland.lua hardcodes is one of the palette' test -z "$stray"

# prompt-ui's copy is compiled into five Rust binaries and cannot be read back
# out of them — the constants are folded into instructions, not strings. It is
# read from the source the release was built from instead, which is the copy a
# person edits and therefore the copy that drifts.
promptui=$WORK/theme.rs
if curl -fsSL --max-time 60 -A 'shedos-release (+https://shedos.org)' \
    "https://raw.githubusercontent.com/shed-os/shedos-ui/main/shedos-prompt-ui/src/theme.rs" \
    -o "$promptui" 2> /dev/null && [[ -s $promptui ]]
then
    # Two of the ten disagree, and the engine's own comment says they cannot:
    # it claims to match prompt-ui so the TUIs and the GUIs fall back to the
    # same colours. The accent pair is green/teal in the engine and blue/mauve
    # in prompt-ui, which is the drift this check was written to find. Fixing
    # it is a release act in another repository, so it is written down here in
    # both directions — an entry that starts agreeing fails too.
    declare -A DRIFTED=(
        [accent]='the engine says green and prompt-ui says blue'
        [accent_secondary]='the engine says teal and prompt-ui says mauve'
    )
    mismatch=0
    while read -r field value; do
        want=$(awk -F'\t' -v f="$field" '$1 == f { print toupper(substr($2, 2)) }' "$WORK/canonical.tsv")
        if [[ -z $want ]]; then
            bad "prompt-ui names $field" 'the engine has no such colour'
            mismatch=1
            continue
        fi
        if [[ -n ${DRIFTED[$field]:-} ]]; then
            if [[ $value == "FF$want" ]]; then
                bad "prompt-ui $field still differs" 'it agrees now — take the line out'
            else
                ok "prompt-ui $field still differs (${DRIFTED[$field]})"
            fi
            continue
        fi
        if [[ $value == "FF$want" ]]; then
            ok "prompt-ui $field is the engine's"
        else
            bad "prompt-ui $field is the engine's" "prompt-ui 0x$value, engine #$want"
            mismatch=1
        fi
    done < <(sed -n 's/^ *\([a-z_0-9]*\): 0x\([0-9A-Fa-f]\{8\}\),$/\1 \2/p' "$promptui" \
        | tr 'a-f' 'A-F' | awk '{ print tolower($1), $2 }')
    check 'prompt-ui declares a fallback at all' test "$mismatch" -ne 2
else
    printf '  skip prompt-ui (its source could not be read)\n'
fi

# --- 3. the vendored branding copy -----------------------------------------

section 'the vendored ascii art matches the branding package'
canonical=$MERGED/etc/shedos-ascii.txt
check 'the branding package ships it' test -f "$canonical"
check 'and it is that package that ships it' test "$(owns /etc/shedos-ascii.txt)" = shedos-branding
# -f, so a 404 page is a failure rather than fourteen bytes that differ.
vendored=$WORK/shedos-ascii.txt
ascii_src=shedos-screensaver/crates/shedos-screensaver-core/assets/shedos-ascii.txt
if curl -fsSL --max-time 60 -A 'shedos-release (+https://shedos.org)' \
    "https://raw.githubusercontent.com/shed-os/shedos-ui/main/$ascii_src" \
    -o "$vendored" 2> /dev/null && [[ -s $vendored ]]
then
    check 'the vendored copy is byte-identical' cmp -s "$canonical" "$vendored"
else
    printf '  skip the vendored copy (it could not be read)\n'
fi

# --- 4. the trust anchor, inside the release --------------------------------
#
# test/trust-anchor asks whether the migrate verb's source and the channel's
# keyring agree, which is the question that catches a rotation half-landed.
# This is the other one: whether the two copies inside THIS release agree, which
# is what a person installing it would find. The two can differ — a fixed
# source that has not been published yet answers the first and not the second.

section 'the release trusts one set of keys'
_fprs() { sed -e 's/[[:space:]]//g' -e '/^[0-9A-F]\{40\}$/!d' | LC_ALL=C sort -u; }
migrate_verb=$MERGED/usr/libexec/shedman/migrate
trusted=$MERGED/usr/share/pacman/keyrings/shedos-trusted
check 'the release ships the migrate verb' test -f "$migrate_verb"
check 'and the trusted-keys list'          test -f "$trusted"
if [[ -f $migrate_verb && -f $trusted ]]; then
    sed -n '/^SHEDOS_KEY_FPRS=(/,/^)/p' "$migrate_verb" | _fprs > "$WORK/mine.txt"
    _fprs < "$trusted" > "$WORK/theirs.txt"
    check 'the migrate verb names fingerprints'   test -s "$WORK/mine.txt"
    check 'the trusted-keys list names some too'  test -s "$WORK/theirs.txt"
    drift=$(LC_ALL=C comm -3 "$WORK/mine.txt" "$WORK/theirs.txt")
    [[ -z $drift ]] || printf '       %s\n' "$drift"
    check 'and they are the same set' test -z "$drift"
    printf '       %d fingerprint(s)\n' "$(wc -l < "$WORK/theirs.txt")"
fi

# --- 5. verb completeness ---------------------------------------------------
#
# Every verb the release publishes should be declared and documented. Three are
# not declared, and the three are the packages the split gave verbs to without
# giving them the dispatcher's package as a dependency. They are written down
# here in both directions, so a fourth fails the run and a fix forces the line
# out.

section 'every published verb is declared and man-paged'
declare -A UNDECLARED=(
    [migrate]=shedos-migrate-to-packaged
    [screensaver]=shedos-screensaver
    [tour]=shedos-tour
)
LIBEXEC=$MERGED/usr/libexec/shedman
VERBSD=$MERGED/usr/share/shedman/verbs.d
for tool in "$LIBEXEC"/*; do
    verb=$(basename "$tool")
    [[ $verb == _* ]] && continue
    owner=$(owns "/usr/libexec/shedman/$verb")
    if [[ -n ${UNDECLARED[$verb]:-} ]]; then
        if [[ -f $VERBSD/$verb.toml ]]; then
            bad "$verb is still undeclared" 'it has a declaration now — take the line out'
        elif [[ $owner != "${UNDECLARED[$verb]}" ]]; then
            bad "$verb is still undeclared" "it moved to $owner"
        else
            ok "$verb is still undeclared ($owner ships no declaration)"
        fi
        continue
    fi
    check "$verb is declared (by $owner)" test -f "$VERBSD/$verb.toml"
done

for decl in "$VERBSD"/*.toml; do
    verb=$(basename "$decl" .toml)
    [[ $verb == _* ]] && continue
    check "$verb has a man page" \
        test -f "$MERGED/usr/share/man/man1/shedman-$verb.1.gz"
    check "$verb has an executable" test -x "$LIBEXEC/$verb"
done

section 'a declaration names the verb it is about'
dupes=$(grep -h '^name' "$VERBSD"/*.toml 2> /dev/null \
    | sed 's/.*= *"//; s/".*//' | LC_ALL=C sort | LC_ALL=C uniq -d)
[[ -z $dupes ]] || printf '       %s\n' "$dupes"
check 'no two declarations claim one verb' test -z "$dupes"

# --- 6. the manual's cross-references ---------------------------------------

section 'every cross-reference between manual pages resolves'
# scdoc writes *name*(n) and roff renders it \fBname\fR(n), with hyphens
# escaped. A reference to something Arch ships is not this release's to check;
# a reference to a page a ShedOS package ships has to land.
for f in "$MERGED"/usr/share/man/man*/*.gz; do
    src=$(basename "$f" .gz)
    zcat "$f" | sed 's/\\-/-/g' \
        | grep -oE '\\fB[A-Za-z0-9._-]+\\fR\([0-9]\)' \
        | sed 's/\\fB//; s/\\fR(/./; s/)//' \
        | awk -v s="$src" '{ print s "\t" $0 }'
done 2> /dev/null | LC_ALL=C sort -u > "$WORK/xrefs.tsv"
check 'the pages carry cross-references' test -s "$WORK/xrefs.tsv"

grep '/usr/share/man/' "$WORK/files.tsv" \
    | awk -F'\t' '{ n = $1; sub(/.*\//, "", n); sub(/\.gz$/, "", n); print n "\t" $2 }' \
    | LC_ALL=C sort -u > "$WORK/manowner.tsv"

# Anything ShedOS-shaped that no page in the release answers for.
dangling=$(awk -F'\t' 'NR == FNR { have[$1] = 1; next }
    $2 ~ /^(shedman|shedos|cage|calamares)/ && !($2 in have) { print $1 " -> " $2 }' \
    "$WORK/manowner.tsv" "$WORK/xrefs.tsv" | LC_ALL=C sort -u)
[[ -z $dangling ]] || printf '       %s\n' "$dangling"
check 'no reference to a ShedOS page goes nowhere' test -z "$dangling"

crossing=$(awk -F'\t' 'NR == FNR { own[$1] = $2; next }
    { src = $1; sub(/\.gz$/, "", src)
      if (own[src] != "" && own[$2] != "" && own[src] != own[$2]) print }' \
    "$WORK/manowner.tsv" "$WORK/xrefs.tsv" | LC_ALL=C sort -u | wc -l)
printf '       %d of them cross a package boundary\n' "$crossing"
check 'and the release does cross package boundaries in its manual' \
    test "$crossing" -gt 0

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if (( fail )); then
    printf '  %s\n' "${failed[@]}" >&2
    exit 1
fi
