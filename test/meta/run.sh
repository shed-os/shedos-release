#!/usr/bin/env bash
# The metapackage generator. Every case hands the renderer a world of its own
# under SHEDOS_META_ROOT — its own lists, its own closure, its own manifest —
# so what is asserted is the rule and not the state of the release this
# repository happens to be at.
#
# The closure resolver wants root and a pacman database, so what runs here is
# the half of it that does not: which roots it would resolve, and its refusal
# when the conflicts list it cross-checks against is empty. The rest is the
# meta workflow's closure job.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
RENDER=$ROOT/tools/render-meta-depends.sh
RESOLVE=$ROOT/tools/resolve-meta-closure.sh

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0

ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }
not() { ! "$@"; }

check() {
    local desc=$1
    shift
    if "$@"; then ok "$desc"; else bad "$desc"; fi
}

section() { printf '\n── %s\n' "$1"; }

# --- a world of its own ------------------------------------------------------

# The default fixture: two ShedOS packages the channel serves, one of them
# installer-only, an Arch closure of three names with one of them replaced,
# an AUR list with one proprietary entry, and two conflicts.
fixture() {
    FIX=$WORK/root
    rm -rf "$FIX"
    mkdir -p "$FIX/packages/official"

    cat > "$FIX/release-manifest.toml" <<'EOF'
[release]
version = "2026.09.01"

[[package]]
name = "alpha"
repo = "alpha"
ref = "2026.09.01"
pkgver = "2026.09.01"
pkgrel = "3"
sha256 = "1111111111111111111111111111111111111111111111111111111111111111"

[[package]]
name = "shedos-installer"
repo = "shedos-installer"
ref = "2026.09.01"
pkgver = "2026.09.01"
pkgrel = "1"
sha256 = "2222222222222222222222222222222222222222222222222222222222222222"

[[package]]
name = "cage"
repo = "cage"
ref = "0.3.0"
pkgver = "0.3.0"
pkgrel = "4"
sha256 = "3333333333333333333333333333333333333333333333333333333333333333"
EOF

    printf 'bash\ncage\treplaced\nzlib\n' > "$FIX/packages/.meta-closure.txt"
    printf 'yay\nchrome\n' > "$FIX/packages/aur.txt"
    printf 'chrome\n' > "$FIX/packages/aur-norepublish.txt"
    printf 'shedos-installer\n' > "$FIX/packages/installer-only.txt"
    printf 'jack2\ndracut\n' > "$FIX/packages/meta-conflicts.txt"
    printf 'bash\nzlib\ncage\n' > "$FIX/packages/official/base.txt"
    printf 'kf6-config\n' > "$FIX/packages/official/installer.txt"
}

render() { SHEDOS_META_ROOT=$FIX bash "$RENDER" > "$WORK/last.out" 2> "$WORK/last.err"; }

PKGBUILD() { printf '%s' "$FIX/packaging/shedos-meta/PKGBUILD"; }

# One array out of the generated PKGBUILD, one entry per line, quotes gone.
array() {
    awk -v name="$1" '
        $0 == name "=(" { inside = 1; next }
        inside && /^\)/ { exit }
        inside {
            sub(/^[ \t]+/, ""); sub(/^'"'"'/, ""); sub(/'"'"'$/, "")
            print
        }
    ' "$(PKGBUILD)"
}

has()    { array "$1" | grep -qxF "$2"; }
optdep() { array optdepends | grep -q "^$1: proprietary"; }
field()  { awk -F= -v k="$1" '$1 == k { print $2; exit }' "$(PKGBUILD)"; }

# --- case 1: the release the manifest defines --------------------------------

section 'case 1 — the metapackage is the release the manifest names'
fixture
check 'the render succeeds' render
[[ -s $WORK/last.err ]] && cat "$WORK/last.err"
check 'pkgver is the manifest release' test "$(field pkgver)" = 2026.09.01
check 'and a first render starts at pkgrel 1' test "$(field pkgrel)" = 1
check 'no VERSION file is read' not test -e "$FIX/VERSION"
check 'the maintainer is the org' grep -q '^# Maintainer: ShedOS <https://github.com/shed-os>' "$(PKGBUILD)"
check 'and so is the url' grep -qx "url='https://github.com/shed-os/shedos-release'" "$(PKGBUILD)"

# --- case 2: the ShedOS set is the manifest's --------------------------------

section 'case 2 — every package the manifest names is pinned to its release'
check 'the ShedOS package is there at its exact release' has depends 'alpha=2026.09.01-3'
check 'the bare name is not' not has depends alpha
check 'and the Arch closure came through unpinned' has depends bash
check 'the AUR entry is a dependency' has depends yay
check 'the proprietary AUR entry is optional' optdep chrome
check 'and it is not a dependency' not has depends chrome

section 'case 2b — an installer-only package reaches neither list'
check 'not a dependency' not has depends 'shedos-installer=2026.09.01-1'
check 'nor an optional one' not optdep shedos-installer
check 'and not under its bare name either' not has depends shedos-installer

# --- case 3: the local replacement -------------------------------------------

section 'case 3 — a name Arch and the channel both carry resolves to the channel'
check 'the pinned form is a dependency' has depends 'cage=0.3.0-4'
check 'and the bare Arch name is gone' not has depends cage
check 'the closure still resolved its Arch dependencies' has depends zlib

section 'case 3b — an unmarked overlap is refused rather than guessed at'
fixture
printf 'bash\ncage\nzlib\n' > "$FIX/packages/.meta-closure.txt"
check 'the render fails' not render
check 'and names the package' \
    grep -q 'cage is in the closure and the manifest and is not marked replaced' "$WORK/last.err"

section 'case 3c — a marker for a package the channel does not serve is refused'
fixture
printf 'bash\treplaced\ncage\treplaced\nzlib\n' > "$FIX/packages/.meta-closure.txt"
check 'the render fails' not render
check 'and names the package' \
    grep -q 'the closure marks bash replaced and the manifest does not name it' "$WORK/last.err"

section 'case 3d — the metapackage is not a dependency of itself'
# The manifest names every package the channel serves, and once the
# metapackage has been published that includes the metapackage. pacman takes a
# self-dependency without complaint, so nothing downstream would say a word —
# and the first pkgrel bump after a render then ships a package pinning its own
# name at the version before it, which nothing in the channel can satisfy.
fixture
python3 - "$FIX/release-manifest.toml" <<'PYEOF'
import sys
path = sys.argv[1]
open(path, "a").write("""
[[package]]
name = "shedos-meta"
repo = "shedos-release"
ref = "2026.09.01"
pkgver = "2026.09.01"
pkgrel = "1"
sha256 = "4444444444444444444444444444444444444444444444444444444444444444"
""")
PYEOF
check 'the render succeeds' render
[[ -s $WORK/last.err ]] && cat "$WORK/last.err"
check 'the metapackage does not depend on itself' \
    not has depends 'shedos-meta=2026.09.01-1'
check 'nor under its bare name' not has depends shedos-meta
check 'and the other packages are still there' has depends 'alpha=2026.09.01-3'
check 'the name it excludes is the name it builds' \
    grep -qx 'pkgname=shedos-meta' "$(PKGBUILD)"

# --- case 4: pkgrel across renders -------------------------------------------

section 'case 4 — a re-render at the same release keeps the pkgrel it had'
fixture
render
sed -i 's/^pkgrel=1$/pkgrel=6/' "$(PKGBUILD)"
render
check 'the pkgrel survives' test "$(field pkgrel)" = 6
check 'and the release is unchanged' test "$(field pkgver)" = 2026.09.01

section 'case 4b — a release that moved starts again at 1'
sed -i 's/^version = "2026.09.01"/version = "2026.09.02"/' "$FIX/release-manifest.toml"
render
check 'the release moved' test "$(field pkgver)" = 2026.09.02
check 'and the pkgrel reset' test "$(field pkgrel)" = 1

# --- case 5: the conflicts are data ------------------------------------------

section 'case 5 — the conflicts array is the file both tools read'
fixture
render
check 'the file is what came out' \
    test "$(array conflicts | tr '\n' ' ')" = 'jack2 dracut '
printf 'jack2\ndracut\nbooster\n' > "$FIX/packages/meta-conflicts.txt"
render
check 'a name added to the file reaches the metapackage' has conflicts booster
check 'the resolver no longer opens the renderer to find them' \
    not grep -qE '^[[:space:]]*renderer=' "$RESOLVE"
check 'and the array it used to read for them is gone from both' \
    not grep -l shedos_conflicts "$RESOLVE" "$RENDER"

section 'case 5b — an empty conflicts file is refused by both'
fixture
printf '# nothing\n' > "$FIX/packages/meta-conflicts.txt"
check 'the render fails' not render
check 'and says so' grep -q 'names nothing' "$WORK/last.err"

# --- case 6: a manifest that is not one --------------------------------------

section 'case 6 — a manifest the schema refuses stops the render'
fixture
printf '[release]\nversion = "2026.09.01"\n' > "$FIX/release-manifest.toml"
check 'the render fails' not render
check 'and the schema said why' grep -q 'names no packages' "$WORK/last.err"

section 'case 6c — a list that is not there is a refusal and not an empty list'
fixture
rm -f "$FIX/packages/aur-norepublish.txt"
check 'the render fails' not render
check 'and names the file' grep -q 'aur-norepublish.txt is missing' "$WORK/last.err"
check 'nothing was written' not test -e "$(PKGBUILD)"

section 'case 6b — a missing closure names the script that writes it'
fixture
rm -f "$FIX/packages/.meta-closure.txt"
check 'the render fails' not render
check 'and says how to get one' grep -q 'resolve-meta-closure.sh' "$WORK/last.err"

# --- case 7: the resolver's own inputs ---------------------------------------

section 'case 7 — the closure resolver refuses to run unprivileged'
fixture
SHEDOS_META_ROOT=$FIX bash "$RESOLVE" > "$WORK/last.out" 2> "$WORK/last.err"
check 'it stops' test "$?" -ne 0
check 'and names the reason' grep -q 'must be run as root' "$WORK/last.err"

# --- case 5c: the conflicts list itself ---------------------------------------

section 'case 5c — the conflicts the metapackage ships are pinned by name'
# The script that reads this file against the repositories reports and does not
# fail, and it cannot fail on a name going missing without somebody first
# deciding which alternatives a metapackage should forbid. So the file's
# contents are pinned here instead: every name is written down, and one
# disappearing is a change somebody has to make on purpose.
#
# jack2 is the reason the file exists. pacstrap picks alphabetically when it
# has a choice, jack2 beats pipewire-jack, and the transaction then dies on a
# conflict with the provider we do ship.
expected_conflicts=(
    jack2 iptables-legacy booster dracut jdk21-openjdk jdk25-openjdk
    qt6-multimedia-gstreamer pipewire-media-session gnu-free-fonts
    ttf-bitstream-vera ttf-croscore ttf-droid ttf-ibm-plex ttf-input
    ttf-input-nerd ttf-roboto virtualbox-guest-modules-arch
    virtualbox-host-modules-arch
)
shipped_conflicts=$(awk 'NF && $1 !~ /^#/ { print $1 }' "$ROOT/packages/meta-conflicts.txt")
check 'the file names exactly what is written down here' \
    test "$(printf '%s\n' "${expected_conflicts[@]}" | sort | tr '\n' ' ')" \
       = "$(printf '%s\n' "$shipped_conflicts" | sort | tr '\n' ' ')"
shipped_carries() {
    local file=$1 name
    shift
    for name in "$@"; do
        grep -qxF "    '$name'" "$file" || return 1
    done
}
check 'and the metapackage this repository ships carries every one' \
    shipped_carries "$ROOT/packaging/shedos-meta/PKGBUILD" "${expected_conflicts[@]}"

# --- case 8: the committed PKGBUILD is still what the inputs render ----------

section 'case 8 — rendering the committed inputs reproduces the committed PKGBUILD'
# Every case above runs against a fixture, so none of them notices when the
# real inputs and the real output stop agreeing. That is exactly how the
# self-dependency above got in: the manifest gained an entry, the committed
# PKGBUILD was already written, and nothing read the two together. This renders
# what this repository ships and compares it byte for byte.
#
# The committed PKGBUILD is copied in because the render reads it back for the
# pkgrel, which is what the real run does too.
REGEN=$WORK/regen
rm -rf "$REGEN"
mkdir -p "$REGEN/packages/official" "$REGEN/packaging/shedos-meta"
cp "$ROOT/release-manifest.toml" "$REGEN/"
cp "$ROOT/packages/.meta-closure.txt" "$ROOT"/packages/*.txt "$REGEN/packages/"
cp "$ROOT"/packages/official/*.txt "$REGEN/packages/official/"
cp "$ROOT/packaging/shedos-meta/PKGBUILD" "$REGEN/packaging/shedos-meta/PKGBUILD"
SHEDOS_META_ROOT=$REGEN bash "$RENDER" > "$WORK/last.out" 2> "$WORK/last.err"
check 'the render succeeds' test "$?" -eq 0
[[ -s $WORK/last.err ]] && cat "$WORK/last.err"
check 'and what it wrote is what is committed' \
    cmp -s "$REGEN/packaging/shedos-meta/PKGBUILD" "$ROOT/packaging/shedos-meta/PKGBUILD"
[[ -f $REGEN/packaging/shedos-meta/PKGBUILD ]] &&
    diff "$ROOT/packaging/shedos-meta/PKGBUILD" \
        "$REGEN/packaging/shedos-meta/PKGBUILD" | head -5

# --- result ------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
