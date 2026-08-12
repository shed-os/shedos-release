#!/usr/bin/env bash
# build-reference-container.sh probe|build
#
# The half of the reference build that has to be root on a machine of its own.
# build-reference.sh mounts the work directory it prepared at /work and runs
# this inside an archlinux container: `probe` says what building this package
# installs, and `build` builds it once the pins that answer have been fetched.
#
# Both phases install the same dependencies first, so the versions the probe
# reported are the ones the pins are applied over.
set -euo pipefail

phase=${1:-}
crate=$REFERENCE_CRATE

# The build itself runs as this account because a Rust binary records the
# registry paths under its home.
builder=builder

lay_out() {
    local staged dest
    while read -r staged dest; do
        [[ -n $staged ]] || continue
        install -d "$(dirname "$dest")"
        rm -rf "$dest"
        cp -a "/work/tree/$staged" "$dest"
        chown -R "$builder:$builder" "$dest"
    done < /work/layout
}

install_dependencies() {
    local deps
    deps=$(bash -c "set +eu; source $crate/PKGBUILD > /dev/null 2>&1
        printf '%s\n' \"\${depends[@]}\" \"\${makedepends[@]}\"" \
        | sed -e 's/[<>=].*//' -e '/^$/d')
    pacman -Syu --noconfirm
    # shellcheck disable=SC2086  # one target per word is what pacman takes
    pacman -S --needed --noconfirm --asdeps $deps
}

# name-version-release-architecture, the way .BUILDINFO writes it.
installed() {
    for desc in /var/lib/pacman/local/*/desc; do
        awk '/^%NAME%/ { getline name } /^%VERSION%/ { getline version }
             /^%ARCH%/ { getline arch }
             END { print name "-" version "-" arch }' "$desc"
    done | LC_ALL=C sort
}

lay_out
install_dependencies

if [[ $phase == probe ]]; then
    installed > /work/installed
    chown "$HOST_UID" /work/installed
    exit 0
fi
[[ $phase == build ]] || { echo "no phase called $phase" >&2; exit 2; }

shopt -s nullglob
pins=(/work/pins/*.pkg.tar.zst)
shopt -u nullglob
if (( ${#pins[@]} > 0 )); then
    pacman -U --noconfirm "${pins[@]}"
    # Nothing walks them back: makepkg syncs dependencies of its own and the
    # repositories are ahead of every one of these.
    for pin in "${pins[@]}"; do
        pin=${pin##*/}
        printf 'IgnorePkg = %s\n' "${pin%-*-*-*.pkg.tar.zst}" >> /etc/pacman.conf
    done
fi

install -d /etc/makepkg.conf.d
cp /work/makepkg-shedos.conf /etc/makepkg.conf.d/99-shedos.conf

sudo -u "$builder" env HOME="/home/$builder" LC_ALL=C \
    SOURCE_DATE_EPOCH="$REFERENCE_EPOCH" PKGDEST="$crate" \
    MAKEPKG_CONF=/etc/makepkg.conf \
    bash -c 'cd "$1" && makepkg --syncdeps --noconfirm --force' _ "$crate"

for built in "$crate"/*.pkg.tar.zst; do
    case ${built##*/} in *-debug-*) continue ;; esac
    cp "$built" /work/out/
done
chown -R "$HOST_UID" /work/out
