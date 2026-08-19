#!/usr/bin/env bash
# The ISO build's checkable halves.
#
# What is not here is the ISO. Building one wants root, an archiso, forty
# minutes and the whole of Arch; the workflow does that and the boot asserts
# say whether it worked. What this covers is everything that decides what goes
# into it — the package list's release half, the collision check, the profile's
# placeholders, and the two pre-flight checks — because each of those is a way
# to ship a wrong ISO that a green boot would not notice.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
MANIFEST=$ROOT/release-manifest.toml
LIST=$ROOT/archiso/packages.x86_64
PROFILE=$ROOT/archiso
OVERLAPS=$ROOT/tools/check-airootfs-overlaps.sh
DEPS=$ROOT/tools/verify-shedos-deps.sh

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0

ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }

check() {
    local desc=$1
    shift
    if "$@"; then ok "$desc"; else bad "$desc"; fi
}

section() { printf '\n── %s\n' "$1"; }
said() { grep -qF "$1" "$WORK/last.out"; }

# The manifest's names, which several cases below are about.
python3 - "$MANIFEST" > "$WORK/release.txt" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as fh:
    doc = tomllib.load(fh)
for entry in sorted(p["name"] for p in doc["package"]):
    print(entry)
PY

# A package file with a chosen name and a chosen set of paths in it, which is
# what both checks read. bsdtar makes one out of a directory; nothing here
# needs makepkg.
make_package() {
    local name=$1 version=$2
    local dir=$WORK/build/$name
    shift 2
    rm -rf "$dir"
    mkdir -p "$dir"
    {
        printf 'pkgname = %s\n' "$name"
        printf 'pkgver = %s\n' "$version"
    } > "$dir/.PKGINFO"
    local path
    for path in "$@"; do
        case $path in
            depend=*) printf 'depend = %s\n' "${path#depend=}" >> "$dir/.PKGINFO" ;;
            *) mkdir -p "$dir/$(dirname "$path")"; printf 'x\n' > "$dir/$path" ;;
        esac
    done
    mkdir -p "$WORK/pkgs"
    ( cd "$dir" && shopt -s nullglob && members=(*) \
        && bsdtar --format=gnutar -caf "$WORK/pkgs/$name-$version-any.pkg.tar.zst" \
            .PKGINFO "${members[@]}" )
}

reset_pkgs() { rm -rf "$WORK/pkgs"; mkdir -p "$WORK/pkgs"; }

# --- case 1: the list's release half is the manifest ------------------------
#
# The committed list is generated, and its Arch half is resolved against
# repositories that move every day, so only this half can be held to anything
# here. It is also the half that used to be wrong by construction: a four-name
# array plus a shedos-* prefix rule, which a rename or a package without the
# prefix walked straight out of.

section 'case 1 — every package the release names is on the ISO'
awk '/^# --- the release/ { on = 1; next } on && !/^#/ && NF { print $1 }' "$LIST" \
    | LC_ALL=C sort -u > "$WORK/listed.txt"
check 'the list carries a release section' test -s "$WORK/listed.txt"
check 'and it is exactly what the manifest names' \
    diff -q "$WORK/release.txt" "$WORK/listed.txt"

section 'case 1a — a replaced name is listed once, as the release'
check 'cage is in the release section' grep -qx cage "$WORK/listed.txt"
check 'and not also in the Arch section' \
    test 1 -eq "$(awk '!/^#/ && $1 == "cage"' "$LIST" | wc -l)"

section 'case 1b — the list names nothing twice'
awk '!/^#/ && NF { print $1 }' "$LIST" | LC_ALL=C sort > "$WORK/all.txt"
check 'no duplicate entries' \
    test "$(wc -l < "$WORK/all.txt")" -eq "$(LC_ALL=C sort -u "$WORK/all.txt" | wc -l)"

# --- case 2: the collision check -------------------------------------------

section 'case 2 — the overlay does not collide with anything the release ships'
reset_pkgs
make_package shedos-system 1-1 usr/lib/shedos/marker
bash "$OVERLAPS" "$WORK/pkgs" "$PROFILE/airootfs" > "$WORK/last.out" 2>&1
rc=$?
check 'it passes' test "$rc" -eq 0
check 'and says so' said 'no overlay file collides with the release'

section 'case 2a — a release package shipping an overlay path fails the check'
reset_pkgs
make_package shedos-system 1-1 etc/vconsole.conf
bash "$OVERLAPS" "$WORK/pkgs" "$PROFILE/airootfs" > "$WORK/last.out" 2>&1
rc=$?
check 'it fails'              test "$rc" -eq 1
check 'it names the path'     said '/etc/vconsole.conf'
check 'and the package'       said 'shedos-system'

section 'case 2b — a package the manifest does not name is not the ISO repository'
reset_pkgs
make_package shedos-system 1-1 usr/lib/shedos/marker
make_package some-aur-thing 1-1 etc/vconsole.conf
bash "$OVERLAPS" "$WORK/pkgs" "$PROFILE/airootfs" > "$WORK/last.out" 2>&1
rc=$?
check 'the AUR build is not held to the rule' test "$rc" -eq 0

section 'case 2c — the Arch half is reported and does not fail'
reset_pkgs
make_package shedos-system 1-1 usr/lib/shedos/marker
printf 'etc/issue\tcore/filesystem\n' > "$WORK/owners.tsv"
SHEDOS_ARCH_OWNERS=$WORK/owners.tsv bash "$OVERLAPS" "$WORK/pkgs" "$PROFILE/airootfs" \
    > "$WORK/last.out" 2>&1
rc=$?
check 'it still passes'   test "$rc" -eq 0
check 'it names the file' said '/etc/issue'
check 'and its owner'     said 'core/filesystem'
check 'and says the reason is not written down anywhere' said 'not written down'

# --- case 3: the dependency pre-flight -------------------------------------

section 'case 3 — a satisfiable release package passes'
reset_pkgs
make_package shedos-system 1-1 depend=bash depend=git
printf 'git\n' > "$WORK/arch.txt"
SHEDOS_ARCH_NAMES=$WORK/arch.txt bash "$DEPS" "$WORK/pkgs" "$MANIFEST" > "$WORK/last.out" 2>&1
rc=$?
check 'it passes' test "$rc" -eq 0

section 'case 3a — a depend nothing can satisfy fails'
reset_pkgs
make_package shedos-system 1-1 depend=a-package-nobody-has
SHEDOS_ARCH_NAMES=$WORK/arch.txt bash "$DEPS" "$WORK/pkgs" "$MANIFEST" > "$WORK/last.out" 2>&1
rc=$?
check 'it fails'          test "$rc" -eq 1
check 'and names it'      said 'shedos-system  →  a-package-nobody-has'

section 'case 3b — an exact pin on a package the release does not publish fails'
reset_pkgs
make_package shedos-system 1-1 depend=git=2.0.0
SHEDOS_ARCH_NAMES=$WORK/arch.txt bash "$DEPS" "$WORK/pkgs" "$MANIFEST" > "$WORK/last.out" 2>&1
rc=$?
check 'it fails'                test "$rc" -eq 1
check 'and says what the pin does' said 'blocks every update'

section 'case 3c — a pin on a package the release does publish is allowed'
reset_pkgs
make_package shedos-system 1-1 depend=shedos-branding=2026.07.03-1
SHEDOS_ARCH_NAMES=$WORK/arch.txt bash "$DEPS" "$WORK/pkgs" "$MANIFEST" > "$WORK/last.out" 2>&1
rc=$?
check 'it passes' test "$rc" -eq 0

section 'case 3d — a package the manifest does not name is not checked'
reset_pkgs
make_package shedos-system 1-1 depend=git
make_package some-aur-thing 1-1 depend=a-package-nobody-has
SHEDOS_ARCH_NAMES=$WORK/arch.txt bash "$DEPS" "$WORK/pkgs" "$MANIFEST" > "$WORK/last.out" 2>&1
rc=$?
check 'it passes' test "$rc" -eq 0

# --- case 4: the profile's placeholders ------------------------------------
#
# Each of these is substituted by prepare-iso.sh, and each would ship something
# broken if the file it lives in were edited without the substitution moving
# with it: an ISO called shedos-@SHEDOS_VERSION@, a pacman.conf pointing at a
# repository named @SHEDOS_REPO@, an installer still calling itself DEVELOPMENT.

section 'case 4 — the profile carries the placeholders the build substitutes'
check 'profiledef has the version placeholder' \
    grep -q '@SHEDOS_VERSION@' "$PROFILE/profiledef.sh"
check 'pacman.conf.in has the repository placeholder' \
    grep -q '@SHEDOS_REPO@' "$PROFILE/pacman.conf.in"
check 'the offline wrapper has the repository placeholder' \
    grep -q '@SHEDOS_REPO@' "$ROOT/tools/pacman-offline-download.sh"
check 'the version hook has the version placeholder' \
    grep -q '@SHEDOS_VERSION@' \
    "$PROFILE/airootfs/etc/pacman.d/hooks/35-shedos-installer-version.hook"

section 'case 4a — the version hook stamps every key the branding carries'
mkdir -p "$WORK/branding"
cat > "$WORK/branding/branding.desc" <<'EOF'
branding:
    version: "DEVELOPMENT"
    shortVersion: "DEVELOPMENT"
    versionedName: "ShedOS DEVELOPMENT"
    shortVersionedName: "ShedOS DEVELOPMENT"
EOF
exec_line=$(sed -n 's/^Exec = //p' \
    "$PROFILE/airootfs/etc/pacman.d/hooks/35-shedos-installer-version.hook")
exec_line=${exec_line//@SHEDOS_VERSION@/2026.08.09}
exec_line=${exec_line//\/etc\/calamares\/branding\/shedos\/branding.desc/$WORK/branding/branding.desc}
eval "$exec_line" > "$WORK/last.out" 2>&1
check 'version'            grep -qx '    version: "2026.08.09"' "$WORK/branding/branding.desc"
check 'shortVersion'       grep -qx '    shortVersion: "2026.08.09"' "$WORK/branding/branding.desc"
check 'versionedName'      grep -qx '    versionedName: "ShedOS 2026.08.09"' "$WORK/branding/branding.desc"
check 'shortVersionedName' grep -qx '    shortVersionedName: "ShedOS 2026.08.09"' "$WORK/branding/branding.desc"

section 'case 4b — every build-time hook says it must leave the squashfs'
# zzzz99 removes the hooks by grepping for that sentence. One without it runs
# on every installed system for the rest of that install's life.
missing=0
for hook in "$PROFILE"/airootfs/etc/pacman.d/hooks/*.hook; do
    grep -qF 'remove from airootfs' "$hook" || { echo "       $hook"; missing=$((missing + 1)); }
done
check 'all of them carry the marker' test "$missing" -eq 0

# --- case 4c: a variable read before the line that sets it ------------------
#
# The port moved a block that reads the ISO repository above the line that
# names it, and `set -u` killed the build there — forty minutes in, after the
# AUR stage had built all of them. shellcheck sees the assignment and asks
# nothing about where it sits; `bash -n` never evaluates anything. This is the
# check that would have caught it in a second.

section 'case 4c — no script reads a variable it has not set yet'
ORDER=$ROOT/tools/check-script-order.sh

mkdir -p "$WORK/order"
cat > "$WORK/order/bad.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "$LATER"
LATER=here
EOF
bash "$ORDER" "$WORK/order/bad.sh" > "$WORK/last.out" 2>&1
rc=$?
check 'it fails on a read before the set'  test "$rc" -eq 1
check 'and names both lines'               said 'LATER is read here and set at line 4'

cat > "$WORK/order/guarded.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "${LATER:-nothing}"
LATER=here
EOF
bash "$ORDER" "$WORK/order/guarded.sh" > "$WORK/last.out" 2>&1
check 'a read that carries its own default is not one' test $? -eq 0

cat > "$WORK/order/heredoc.sh" <<'OUTER'
#!/usr/bin/env bash
set -euo pipefail
cat <<'EOF'
$pkgver is a literal here
EOF
pkgver=1
OUTER
bash "$ORDER" "$WORK/order/heredoc.sh" > "$WORK/last.out" 2>&1
check 'a quoted heredoc is data and not script' test $? -eq 0

cat > "$WORK/order/read.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
while IFS= read -r line || [[ -n $line ]]; do
    printf '%s\n' "$line"
done < /dev/null
for line in a b; do echo "$line"; done
EOF
bash "$ORDER" "$WORK/order/read.sh" > "$WORK/last.out" 2>&1
check 'a read that sets the variable on the same line is a set' test $? -eq 0

# The live gate. Every script this repository runs, including the ported ones.
shopt -s nullglob
scripts=("$ROOT"/tools/*.sh "$ROOT"/scripts/*.sh "$ROOT"/scripts/lib/*.sh "$ROOT"/publisher/*.sh)
shopt -u nullglob
check 'there are scripts to check' test "${#scripts[@]}" -gt 20
bash "$ORDER" "${scripts[@]}" > "$WORK/last.out" 2>&1
rc=$?
[[ $rc -eq 0 ]] || sed 's/^/       /' "$WORK/last.out"
check 'every script in this repository passes' test "$rc" -eq 0

# --- case 4d: the sweep reads the verb and not its wrapper ------------------
#
# The first ISO that ever built failed this sweep 35 times out of 35, every one
# of them on --help-summary, every one with rc=0. The verbs were right and the
# harness was wrong: it merged the chroot wrapper's stderr into what it treated
# as the verb's output, and arch-chroot says the airootfs is not a mountpoint
# every single time it is called.

section 'case 4d — the chroot wrapper does not speak for the verb'
SWEEP=$ROOT/tools/verb-sweep.sh

sweep_root=$WORK/sweeproot
mkdir -p "$sweep_root/usr/libexec/shedman" "$sweep_root/usr/bin"
# The sweep proves it can enter the root before it blames a verb for anything,
# and it does that by running true in there. A real airootfs has one.
printf '#!/usr/bin/env bash\nexit 0\n' > "$sweep_root/usr/bin/true"
chmod +x "$sweep_root/usr/bin/true"
cat > "$sweep_root/usr/libexec/shedman/demo" <<'EOF'
#!/usr/bin/env bash
case ${1:-} in
    --help-summary) echo 'one line, as the contract says' ;;
    --help) echo 'Usage: shedman demo' ;;
    --complete-*) ;;
    *) exit 2 ;;
esac
EOF
chmod +x "$sweep_root/usr/libexec/shedman/demo"

# A stand-in for arch-chroot that is noisy on stderr exactly the way it is.
cat > "$WORK/chatty-chroot" <<'EOF'
#!/usr/bin/env bash
echo "==> WARNING: $1 is not a mountpoint. This may have undesirable side effects." >&2
r=$1; shift
exec "$r$1" "${@:2}"
EOF
chmod +x "$WORK/chatty-chroot"

SHEDOS_CHROOT=$WORK/chatty-chroot bash "$SWEEP" "$sweep_root" > "$WORK/last.out" 2>&1
rc=$?
check 'a verb that answers correctly passes through a noisy wrapper' test "$rc" -eq 0
check 'and its one-line summary is read as one line' said 'ok   demo --help-summary'

section 'case 4d1 — a verb that really does print two lines still fails'
cat > "$sweep_root/usr/libexec/shedman/demo" <<'EOF'
#!/usr/bin/env bash
case ${1:-} in
    --help-summary) printf 'first line\nsecond line\n' ;;
    --help) echo 'Usage: shedman demo' ;;
    --complete-*) ;;
    *) exit 2 ;;
esac
EOF
chmod +x "$sweep_root/usr/libexec/shedman/demo"
SHEDOS_CHROOT=$WORK/chatty-chroot bash "$SWEEP" "$sweep_root" > "$WORK/last.out" 2>&1
rc=$?
check 'it fails'                    test "$rc" -eq 1
check 'and it is the summary check' said 'FAIL demo --help-summary'

section 'case 4d2 — a chroot nobody can enter is not thirty-five broken verbs'
cat > "$WORK/dead-chroot" <<'EOF'
#!/usr/bin/env bash
echo '==> ERROR: failed to setup chroot' >&2
exit 1
EOF
chmod +x "$WORK/dead-chroot"
SHEDOS_CHROOT=$WORK/dead-chroot bash "$SWEEP" "$sweep_root" > "$WORK/last.out" 2>&1
rc=$?
check 'it is a could-not-check rather than a did-not-hold' test "$rc" -eq 2
check 'and it says which root'  said 'could not enter'
check 'without blaming a verb'  bash -c '! grep -q "FAIL" "$1"' _ "$WORK/last.out"

# --- case 5: what the profile no longer ships ------------------------------

section 'case 5 — the dead pam file is not in the profile'
check 'no hyprlock pam file' test ! -e "$PROFILE/airootfs/etc/pam.d/hyprlock"

section 'case 5a — the profile stages no installer sources'
check 'no /opt installer tree' test ! -e "$PROFILE/airootfs/opt/shedos-installer"
check 'no calamares configuration' test ! -e "$PROFILE/airootfs/etc/calamares"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
