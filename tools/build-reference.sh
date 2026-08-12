#!/usr/bin/env bash
# build-reference.sh [--compare] <monolith> <candidate.pkg.tar.zst> [<commit>]
#
# Build the monolith's version of a package the way the pipeline built the
# candidate, so that compare-package.sh has something to compare against.
# What the build needs is read out of the candidate and the carve maps rather
# than written down a second time: which monolith directory holds the source,
# what has to sit around it, where the tree goes, and which package versions
# this machine would otherwise get wrong.
#
# The commit defaults to the monolith clone's HEAD. An expectation written
# against an older one names it, and passing it here is how that reference is
# rebuilt later.
#
# With --compare the reference goes straight into compare-package.sh against
# the candidate, with the package's own expectation file, and this exits with
# whatever that says.
#
# The README's "Building the reference" says why each of these matters.
#
# SHEDOS_REFERENCE_MAPS_DIR, SHEDOS_REFERENCE_CARVED_DIR,
# SHEDOS_REFERENCE_INSTALLED and SHEDOS_REFERENCE_ARCHIVE replace the maps
# directory, the carved PKGBUILD fetch, the container probe and the package
# archive; SHEDOS_REFERENCE_DIR names the work directory and
# SHEDOS_REFERENCE_DRY_RUN stops once the plan is made. That is how the suite
# beside this runs offline.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tools/lib-carve-maps.sh
source "$ROOT/tools/lib-carve-maps.sh"

ARCHIVE=${SHEDOS_REFERENCE_ARCHIVE:-https://archive.archlinux.org/packages}
CHANNELS=$CARVED_RAW/shedos-ci/main/scripts/enable-shedos-channels.sh

die() { printf 'reference: %s\n' "$*" >&2; exit 2; }

compare=
while (( $# )); do
    case $1 in
        --compare) compare=yes; shift ;;
        --*) die "unknown option $1" ;;
        *) break ;;
    esac
done

(( $# == 2 || $# == 3 )) \
    || die 'usage: build-reference.sh [--compare] <monolith> <candidate> [<commit>]'
mono=$1 candidate=$2
[[ -f $candidate ]] || die "$candidate does not exist"
[[ -d $mono/.git ]] || die "$mono is not a git repository"
commit=$(git -C "$mono" rev-parse --verify --quiet "${3:-HEAD}^{commit}") \
    || die "$mono has no commit ${3:-HEAD}"

work=${SHEDOS_REFERENCE_DIR:-$(mktemp -d)}
mkdir -p "$work"

# --- what the candidate says about itself -----------------------------------

bsdtar -xOf "$candidate" .PKGINFO > "$work/PKGINFO"
bsdtar -xOf "$candidate" .BUILDINFO > "$work/BUILDINFO"

meta() { sed -n "s/^$2 = //p" "$work/$1"; }

pkgname=$(meta PKGINFO pkgname | head -1)
release=$(meta PKGINFO pkgver | head -1)
pkgver=${release%-*}
pkgrel=${release##*-}
epoch=$(meta PKGINFO builddate | head -1)
builddir=$(meta BUILDINFO builddir | head -1)
[[ -n $pkgname && -n $pkgver && -n $pkgrel && -n $epoch && -n $builddir ]] \
    || die "$candidate does not carry the .PKGINFO and .BUILDINFO fields a reference needs"

expected=$ROOT/tools/expected-diffs/$pkgname.txt
if [[ -n $compare && ! -f $expected ]]; then
    die "$expected does not exist"
fi

# --- which monolith directory builds it -------------------------------------

pairs=$work/pairs
: > "$pairs"
problem=$(derive_pairs "$pairs" "${SHEDOS_REFERENCE_MAPS_DIR:-$ROOT/tools/carve-maps}" '') \
    || die "$problem"

package_dir='' carved_repo='' carved_subdir=''
while read -r repo path subdir; do
    [[ -n ${repo//[[:space:]]/} ]] || continue
    git -C "$mono" show "$commit:$path/PKGBUILD" > "$work/monolith.PKGBUILD" 2>/dev/null \
        || continue
    [[ $(pkgbuild_field "$work/monolith.PKGBUILD" pkgname) == "$pkgname" ]] || continue
    [[ -z $package_dir ]] || die "$package_dir and $path both build $pkgname"
    package_dir=$path carved_repo=$repo carved_subdir=$subdir
done < "$pairs"
[[ -n $package_dir ]] || die "no carve map names a packaging directory building $pkgname"
carved=$carved_repo${carved_subdir:+/$carved_subdir}

git -C "$mono" show "$commit:$package_dir/PKGBUILD" > "$work/monolith.PKGBUILD"
monolith_version=$(pkgbuild_field "$work/monolith.PKGBUILD" pkgver) \
    || die "$package_dir names no pkgver"
[[ $monolith_version == "$pkgver" ]] \
    || die "the candidate is $pkgname $pkgver and $package_dir is at $monolith_version"

# --- where the build has to run ---------------------------------------------

# Cargo builds a package id out of the absolute path of the tree, so a
# reference built anywhere else differs in .text. That path is the candidate's
# builddir plus whatever the carved PKGBUILD's build() steps into under
# $srcdir, which is the only place it is written down.
rc=0
read_pkgbuild "${SHEDOS_REFERENCE_CARVED_DIR:-}" "$carved" \
    "$CARVED_RAW/$carved_repo/main/${carved_subdir:+$carved_subdir/}PKGBUILD" \
    "$work/carved.PKGBUILD" || rc=$?
case $rc in
    0) ;;
    3) die "$carved holds no PKGBUILD" ;;
    *) die "could not read the PKGBUILD in $carved" ;;
esac

under_srcdir=$(awk '/^[[:space:]]*build\(\)/ { inside = 1; next }
     inside && /^}/ { exit }
     inside && match($0, /cd[[:space:]]+"?\$\{?srcdir\}?\//) {
         rest = substr($0, RSTART + RLENGTH)
         sub(/["[:space:]].*/, "", rest)
         print rest
         exit
     }' "$work/carved.PKGBUILD")
if [[ -z $under_srcdir ]] && grep -q '^source=' "$work/carved.PKGBUILD"; then
    die "nothing in $carved/PKGBUILD says where under \$srcdir the build runs"
fi
crate=$builddir${under_srcdir:+/src/$under_srcdir}

# --- what has to sit around it ----------------------------------------------

normalise() {
    local part joined='' out=()
    local -a parts
    IFS=/ read -ra parts <<<"$1"
    for part in "${parts[@]}"; do
        case $part in
            '' | .) ;;
            ..) unset 'out[-1]' ;;
            *) out+=("$part") ;;
        esac
    done
    (( ${#out[@]} == 0 )) || joined=$(IFS=/; printf '%s' "${out[*]}")
    if [[ $1 == /* ]]; then printf '/%s\n' "$joined"; else printf '%s\n' "$joined"; fi
}

# Every crate the package reaches by path, laid out around it the way the
# carved repo lays them out, or the build stops at a Cargo.toml it cannot read.
declare -A destination=()
collect() {
    local dir=$1 dest=$2 rel target toml
    [[ -z ${destination[$dir]:-} ]] || return 0
    destination[$dir]=$dest
    toml=$(git -C "$mono" show "$commit:$dir/Cargo.toml" 2>/dev/null) || return 0
    while IFS= read -r rel; do
        [[ -n $rel ]] || continue
        target=$(normalise "$dir/$rel")
        if [[ $target != "$dir" && $target != "$dir"/* ]]; then
            collect "$target" "$(normalise "$dest/$rel")"
        fi
    done < <(grep -oE 'path[[:space:]]*=[[:space:]]*"[^"]+"' <<<"$toml" \
        | sed 's/.*"\(.*\)"/\1/')
}
collect "$package_dir" "$crate"

# --- the tree, from the commit and never the working tree -------------------

rm -rf "$work/stage" "$work/tree"
mkdir -p "$work/stage" "$work/tree"
git -C "$mono" archive "$commit" "${!destination[@]}" | tar -x -C "$work/stage"

: > "$work/layout"
for dir in "${!destination[@]}"; do
    staged=${destination[$dir]##*/}
    [[ ! -e $work/tree/$staged ]] \
        || die "$dir and another crate would both be laid out as $staged"
    mv "$work/stage/$dir" "$work/tree/$staged"
    printf '%s %s\n' "$staged" "${destination[$dir]}" >> "$work/layout"
done

# The candidate's release, because the carve republishes past the monolith
# without a release behind it and pkgrel is a .PKGINFO field.
sed -i -E "s/^pkgrel=.*/pkgrel=$pkgrel/" "$work/tree/${crate##*/}/PKGBUILD"

# What makepkg was configured with, taken from the candidate rather than from a
# copy of the pipeline's drop-in that could drift away from it.
{
    printf 'BUILDENV=(%s)\n' "$(meta BUILDINFO buildenv | paste -sd' ' -)"
    printf 'OPTIONS=(%s)\n' "$(meta BUILDINFO options | paste -sd' ' -)"
    printf 'MAKEFLAGS="-j$(nproc)"\n'
} > "$work/makepkg-shedos.conf"

# --- the container ----------------------------------------------------------

image=
in_container() {
    docker run --rm --network host \
        -v "$work:/work" -v "$work/pkgcache:/var/cache/pacman/pkg" \
        -v "$ROOT/tools/build-reference-container.sh:/steps.sh:ro" \
        -e "REFERENCE_CRATE=$crate" -e "REFERENCE_EPOCH=$epoch" \
        -e "HOST_UID=$(id -u)" "$image" bash /steps.sh "$1"
}

prepare_container() {
    command -v docker > /dev/null || die 'there is no docker on this machine'
    mkdir -p "$work/image" "$work/pkgcache" "$work/out"
    curl -fsSL -A "$USER_AGENT" -o "$work/image/enable-shedos-channels.sh" "$CHANNELS" \
        || die "could not download the pipeline's channel script from $CHANNELS"
    cat > "$work/image/Dockerfile" <<'EOF'
FROM archlinux:latest
COPY enable-shedos-channels.sh /enable-shedos-channels.sh
RUN touch /.shedos-build-environment && \
    pacman -Syu --noconfirm && \
    pacman -S --needed --noconfirm base-devel git sudo jq curl && \
    pacman-key --init && \
    pacman-key --populate archlinux && \
    useradd -m builder && \
    bash /enable-shedos-channels.sh
EOF
    image=shedos-reference:$(cat "$work/image"/* | sha256sum | cut -c1-12)
    if docker image inspect "$image" > /dev/null 2>&1; then return 0; fi
    docker build --network host -t "$image" "$work/image" || die "could not build $image"
}

# --- the environment the candidate recorded ---------------------------------

# The probe installs what the PKGBUILD asks for and says what that left
# installed. The build does the same before it applies anything, so a pin is
# computed against the state it lands on.
installed=$work/installed
if [[ -n ${SHEDOS_REFERENCE_INSTALLED:-} ]]; then
    cp -- "$SHEDOS_REFERENCE_INSTALLED" "$installed"
else
    prepare_container
    in_container probe || die 'the container could not say what it would install'
fi

# Only a package this build installs at another version is pinned. One the
# candidate had and this build never installs is not what compiled it, and a
# version the current repositories still serve needs nothing done.
sed -E 's/-[^-]+-[^-]+-[^-]+$//' "$installed" | LC_ALL=C sort -u > "$work/installed.names"
pins=()
while IFS= read -r want; do
    [[ -n $want ]] || continue
    if grep -qxF "$want" "$installed"; then continue; fi
    grep -qxF "${want%-*-*-*}" "$work/installed.names" || continue
    pins+=("$want")
done < <(meta BUILDINFO installed)

# --- the plan ---------------------------------------------------------------

printf 'package  %s %s-%s\n' "$pkgname" "$pkgver" "$pkgrel"
printf 'source   %s at %s\n' "$package_dir" "$commit"
printf 'carved   %s\n' "$carved"
printf 'crate    %s\n' "$crate"
for dir in "${!destination[@]}"; do
    [[ $dir == "$package_dir" ]] || printf 'beside   %s at %s\n' "$dir" "${destination[$dir]}"
done
printf 'epoch    %s\n' "$epoch"
for want in ${pins[@]+"${pins[@]}"}; do
    printf 'pin      %s\n' "$want"
done

mkdir -p "$work/pins"
for want in ${pins[@]+"${pins[@]}"}; do
    name=${want%-*-*-*}
    curl -fsSL -A "$USER_AGENT" -o "$work/pins/$want.pkg.tar.zst" \
        "$ARCHIVE/${name:0:1}/$name/$want.pkg.tar.zst" \
        || die "$want is on no mirror and not on the archive"
done

[[ -z ${SHEDOS_REFERENCE_DRY_RUN:-} ]] || exit 0

# --- the build --------------------------------------------------------------

[[ -n $image ]] || prepare_container
in_container build || die 'the reference build failed'

reference=$(find "$work/out" -name "$pkgname-$pkgver-$pkgrel-*.pkg.tar.zst" -print -quit)
[[ -n $reference ]] || die "the build produced no $pkgname-$pkgver-$pkgrel"

# Anything left over belongs to the package rather than to the builder only if
# the same packages compiled both sides, so the run says whether they did.
bsdtar -xOf "$reference" .BUILDINFO | sed -n 's/^installed = //p' | LC_ALL=C sort \
    > "$work/reference.installed"
meta BUILDINFO installed | LC_ALL=C sort > "$work/candidate.installed"
if LC_ALL=C comm -3 "$work/candidate.installed" "$work/reference.installed" | grep -q .; then
    printf 'buildinfo only in the candidate: %s\n' \
        "$(LC_ALL=C comm -23 "$work/candidate.installed" "$work/reference.installed" \
            | paste -sd' ' -)"
    printf 'buildinfo only in the reference: %s\n' \
        "$(LC_ALL=C comm -13 "$work/candidate.installed" "$work/reference.installed" \
            | paste -sd' ' -)"
else
    printf 'buildinfo the same packages in both directions\n'
fi

printf 'reference %s\n' "$reference"
[[ -n $compare ]] || exit 0
exec bash "$ROOT/tools/compare-package.sh" "$reference" "$candidate" "$expected"
