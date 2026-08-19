#!/usr/bin/env bash
# The release-level integration tier: what only becomes a question once the
# packages are separate things.
#
# Four suites in the monolith asked these — smoke, shedman, shell-migrate and
# kernel — by reading two or three package trees out of one checkout. Their
# carves kept the half that is about one package and dropped the half that
# crosses them, because a repository holding one package has nothing to hold
# the others against. This is where that half lives, and it reads the released
# packages rather than any tree: the release is what these are about.
#
# The whole release is unpacked into one directory, which is also the shape an
# install has. That is the first assertion here and the reason the rest can be
# written at all.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
MANIFEST=$ROOT/release-manifest.toml

WORK=$(mktemp -d)
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

pass=0
fail=0
failed=()

ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s — %s\n' "$1" "${2:-}"; fail=$((fail + 1)); failed+=("$1"); }

check() {
    local desc=$1
    shift
    if "$@"; then ok "$desc"; else bad "$desc"; fi
}

section() { printf '\n── %s\n' "$1"; }

# --- the release, unpacked --------------------------------------------------

if [[ ${SHEDOS_SKIP_LIVE:-0} == 1 ]]; then
    echo 'integration: SKIP — SHEDOS_SKIP_LIVE'
    exit 0
fi
if ! curl -sS -I -m 20 https://repo.shedos.org/staging/test/x86_64/shedos.db.tar.gz \
        > /dev/null 2>&1 && [[ -z ${SHEDOS_MANIFEST_CHANNEL:-} ]]; then
    echo 'integration: SKIP — the channel is unreachable'
    exit 0
fi

PKGS=$WORK/pkgs
if ! bash "$ROOT/tools/fetch-packages.sh" "$MANIFEST" "$PKGS" > "$WORK/fetch.log" 2>&1; then
    echo 'integration: could not fetch the release' >&2
    tail -20 "$WORK/fetch.log" >&2
    exit 1
fi

# "<path>\t<package>" for everything the release ships.
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

section 'the release co-installs'
# pacman refuses a transaction where two packages claim one path, so a release
# whose own packages collide cannot be installed at all — and nothing else
# asks, because each repository only knows what it ships.
cut -f1 "$WORK/files.tsv" | LC_ALL=C uniq -d > "$WORK/claimed-twice.txt"
if [[ -s $WORK/claimed-twice.txt ]]; then
    while read -r path; do
        printf '       %s\t%s\n' "$path" \
            "$(awk -F'\t' -v p="$path" '$1 == p { print $2 }' "$WORK/files.tsv" | paste -sd,)"
    done < "$WORK/claimed-twice.txt"
fi
check 'no path is claimed by two packages' test ! -s "$WORK/claimed-twice.txt"
printf '       %d files across %d packages\n' \
    "$(wc -l < "$WORK/files.tsv")" "$(find "$PKGS" -name '*.pkg.tar.zst' | wc -l)"

owns() {  # which package ships $1, empty when none does
    awk -F'\t' -v p="$1" '$1 == p { print $2; exit }' "$WORK/files.tsv"
}

LIBEXEC=$MERGED/usr/libexec/shedman
export SHEDOS_LIB_ROOT=$MERGED/usr/lib/shedos

# --- the verb contract, over every verb the release publishes ---------------
#
# The monolith's smoke suite named nine tools out of three package trees. The
# release knows its own roster, so this asks every verb rather than a list
# somebody has to remember to extend.

# Two answers used to be wrong here and were written down rather than checked
# less strictly: health --help printed neither a usage line nor the program
# name, and migrate --complete-fish exited 2 on an option the other two shells
# got. Both were fixed in the repositories that own them and published, and the
# entries came out with them. Nothing is exempt now.
contract() {
    local label=$1 outcome=$2 detail=${3:-}
    if (( outcome )); then ok "$label"; else bad "$label" "$detail"; fi
}

# A verb is asked where it stands, which is an unpacked tree rather than an
# install. Two kinds of answer are not the verb's fault there: a Python verb
# whose package declares a module that is not in this container, and a shim that
# execs an absolute path only an install provides. Both are reported by name and
# counted rather than passed over, and every other failure is a failure.
#
# The full sweep — every verb on a machine where the whole release is installed
# — belongs to the ISO build, which pacstraps exactly that.
notaskable=0
_why_not() {
    local out=$1
    if [[ $out == *ModuleNotFoundError:* ]]; then
        printf 'needs the module %s\n' "$(sed -n "s/.*No module named '\([^']*\)'.*/\1/p" <<<"$out" | head -1)"
        return 0
    fi
    if [[ $out == *"No such file or directory"* && $out == */usr/* ]]; then
        printf 'execs a path only an install has\n'
        return 0
    fi
    return 1
}

section 'every published verb answers the dispatcher contract'
verbs=()
for tool in "$LIBEXEC"/*; do
    name=$(basename "$tool")
    [[ $name == _* ]] && continue
    verbs+=("$name")
done
check 'the release publishes verbs at all' test "${#verbs[@]}" -gt 0

for verb in "${verbs[@]}"; do
    tool=$LIBEXEC/$verb
    if [[ ! -x $tool ]]; then
        bad "$verb is executable" "not executable"
        continue
    fi
    out=$(timeout 20 "$tool" --help-summary 2>&1); rc=$?
    if (( rc != 0 )) && why=$(_why_not "$out"); then
        printf '       %s could not be asked here: %s\n' "$verb" "$why"
        notaskable=$((notaskable + 1))
        continue
    fi
    good=0
    (( rc == 0 )) && [[ -n ${out//[[:space:]]/} ]] && (( $(wc -l <<<"$out") == 1 )) && good=1
    contract "$verb --help-summary" "$good" "rc=$rc out=${out:0:100}"

    out=$(timeout 20 "$tool" --help 2>&1); rc=$?
    good=0
    (( rc == 0 )) && grep -qiE 'usage|shedman' <<<"$out" && good=1
    contract "$verb --help" "$good" "rc=$rc out=${out:0:100}"

    for mode in --complete-bash --complete-zsh --complete-fish; do
        good=0
        timeout 20 "$tool" "$mode" > /dev/null 2>&1 && good=1
        contract "$verb $mode" "$good" 'non-zero'
    done
done
printf '       %d of %d verbs answered; %d could not be asked in this container\n' \
    "$(( ${#verbs[@]} - notaskable ))" "${#verbs[@]}" "$notaskable"

# --- the dispatcher, over the roster several packages built -----------------

section 'the dispatcher drives verbs from every package that ships one'
dispatcher=$MERGED/usr/bin/shedman
check 'the release ships a dispatcher' test -x "$dispatcher"

# It takes its roster and its declarations from the config file, which is the
# seam the split introduced: point both at the unpacked release and the
# dispatcher drives the whole of it with nothing of its own rewritten.
cat > "$WORK/shedman.toml" <<EOF
libexec = "$LIBEXEC"
verbs = "$MERGED/usr/share/shedman/verbs.d"
package = "shedman"
EOF
export SHEDMAN_CONFIG=$WORK/shedman.toml
wrapper=$dispatcher

listing=$("$wrapper" 2>&1) || true
check 'it lists subcommands' grep -q '^Available subcommands:' <<<"$listing"
# One verb from each of four packages, so a listing that only sees the verbs of
# the package the dispatcher ships in cannot pass.
for verb in update dock theme encrypt; do
    owner=$(awk -F'\t' -v v="/usr/libexec/shedman/$verb" '$1 == v { print $2 }' "$WORK/files.tsv")
    check "the listing has $verb (from $owner)" grep -q "^  $verb " <<<"$listing"
done
check 'and hides the underscored helpers' \
    bash -c "! grep -Eq '^  _' <<<\"\$1\"" _ "$listing"

help_out=$("$wrapper" help 2>&1) || true
check 'help is the same as the bare listing' test "$listing" = "$help_out"

a=$("$wrapper" help update 2>&1) || true
b=$("$wrapper" update --help 2>&1) || true
check 'help <verb> forwards to the verb' bash -c '[[ -n $1 && $1 == "$2" ]]' _ "$a" "$b"

unknown=$("$wrapper" updat 2>&1); rc=$?
check 'an unknown verb exits 2'   test "$rc" -eq 2
check 'and suggests the near one' grep -q 'Did you mean' <<<"$unknown"
check 'naming it'                 grep -q '  update' <<<"$unknown"

version=$("$wrapper" version 2>&1) || true
check 'version prints something' test -n "$version"

section 'every shim points at a verb some package ships'
shims=0
for shim in "$MERGED"/usr/bin/shedos-*; do
    [[ -f $shim ]] || continue
    grep -q '^exec /usr/bin/shedman ' "$shim" 2>/dev/null || continue
    shims=$((shims + 1))
    name=$(basename "$shim")
    verb=$(awk '/^exec \/usr\/bin\/shedman /{ print $3; exit }' "$shim")
    if [[ ! -x $shim ]]; then
        bad "$name is executable" 'not executable'
        continue
    fi
    if [[ -x $LIBEXEC/$verb ]]; then
        ok "$name → $verb"
    else
        bad "$name → $verb" 'no package ships that verb'
    fi
done
check 'the release ships shims' test "$shims" -gt 0

# --- shell-migrate: one package's tool over another package's files ---------
#
# The tool is shedos-system's and everything it touches is somebody else's: the
# stock pair it is allowed to overwrite belongs to Arch's bash package, and the
# pair it seeds is the desktop package's, which that package's scriptlet copies
# into /etc/skel because bash owns those two paths and it cannot ship them.

section 'shell-migrate seeds the pair the desktop package ships'
tool=$MERGED/usr/lib/shedos/shell-migrate
check 'the release ships the tool' test -x "$tool"
defaults=$MERGED/usr/share/shedos/hyprland/defaults
check 'and the desktop package ships the bash pair' \
    bash -c '[[ -f $1/.bashrc && -f $1/.bash_profile ]]' _ "$defaults"

if [[ -x $tool && -f $defaults/.bashrc ]]; then
    sm=$WORK/sm
    mkdir -p "$sm/bin" "$sm/skel" "$sm/homes/home/alice" "$sm/homes/home/bob"
    cp "$defaults/.bashrc" "$defaults/.bash_profile" "$sm/skel/"
    # /etc/skel is what the desktop package's scriptlet leaves behind, which is
    # its own copy of the pair — the fixture is that state, not an invention.
    printf '#!/usr/bin/env bash\necho "$*" >> %s/chsh.log\n' "$sm" > "$sm/bin/chsh"
    printf '#!/usr/bin/env bash\necho "$*" >> %s/systemctl.log\n' "$sm" > "$sm/bin/systemctl"
    chmod +x "$sm/bin"/*
    # alice carries the stock file the tool records a hash for, bob his own.
    stock=$(awk '/^STOCK_SHA=\(/{ getline; while ($0 !~ /^\)/) { print $1; getline } }' "$tool" \
        | head -1)
    printf '# not the stock file\n' > "$sm/homes/home/alice/.bashrc"
    printf '# my own\n' > "$sm/homes/home/bob/.bashrc"
    cat > "$sm/passwd" <<EOF
root:x:0:0::/root:/usr/bin/bash
alice:x:1000:1000::/home/alice:/usr/bin/zsh
bob:x:1001:1001::/home/bob:/usr/bin/zsh
carol:x:1002:1002::/home/carol:/usr/bin/bash
EOF
    : > "$sm/chsh.log"; : > "$sm/systemctl.log"
    PATH="$sm/bin:$PATH" SHEDOS_SM_PASSWD=$sm/passwd SHEDOS_SM_SKEL=$sm/skel \
        SHEDOS_SM_HOME_ROOT=$sm/homes bash "$tool" > "$sm/out" 2>&1

    check 'it records a stock hash to compare against' \
        bash -c '[[ $1 =~ ^[0-9a-f]{64}$ ]]' _ "$stock"
    check 'a zsh user is moved to bash' \
        grep -qx -- '-s /usr/bin/bash alice' "$sm/chsh.log"
    check 'a bash user is left alone' \
        bash -c '! grep -q carol "$1"' _ "$sm/chsh.log"
    check "a customized file is kept" \
        bash -c '[[ $(cat "$1") == "# my own" ]]' _ "$sm/homes/home/bob/.bashrc"
    check 'and the tool disarms itself' \
        grep -q 'disable shedos-shell-migrate' "$sm/systemctl.log"
fi

# --- what the boot harnesses reach for --------------------------------------
#
# The QEMU harnesses inject shipped code into a guest, and they name the files
# by path. A carve that moves one to another package does not break the harness
# where anyone can see it — it breaks forty minutes into an ISO build, once,
# and only for whoever reads that log. The emergency harness found exactly that
# the first time it ran on a real image: its recovery tool imports apply_core,
# which the split moved to shedman.
#
# The paths are parsed out of the harnesses rather than copied here, so a file
# added to one of them is checked without anybody remembering to.

section 'every file the boot harnesses inject is in the release'
harness_paths=$(
    # encrypt-harness: the `for f in …; do` list, the esp-state install, and the
    # unit names its `for s in …` loop expands under /usr/lib/systemd/system.
    awk '/^ *for f in usr\//,/; do/' "$ROOT/scripts/lib/encrypt-harness.sh" \
        | tr ' \\' '\n\n' | grep '^usr/'
    grep -oE '"\$tree/[^"]+"' "$ROOT/scripts/lib/encrypt-harness.sh" \
        | sed 's|"\$tree/||; s|"$||' | grep -v '\$'
    awk '/^ *for s in shedos-/,/; do/' "$ROOT/scripts/lib/encrypt-harness.sh" \
        | tr ' ' '\n' | grep '^shedos-' | sed 's/;$//' \
        | sed 's|^|usr/lib/systemd/system/|; s|$|.service|'
    # emergency: the library directory it runs the tool out of.
    printf 'usr/lib/shedos/emergency-recovery-ui.py\nusr/lib/shedos/apply_core.py\n'
) 
# The `; do` that ends each list arrives glued to its last element.
harness_paths=$(printf '%s\n' "$harness_paths" \
    | sed 's/;$//' | grep -vE '^(do|)$' | LC_ALL=C sort -u)
count=$(printf '%s\n' "$harness_paths" | grep -c .)
check 'the harnesses name files at all' test "$count" -ge 12

missing=0
while read -r rel; do
    [[ -n $rel ]] || continue
    if [[ -n $(owns "/$rel") ]]; then
        continue
    fi
    printf '       /%s is injected by a harness and no package ships it\n' "$rel"
    missing=$((missing + 1))
done <<< "$harness_paths"
check "all $count of them are shipped by the release" test "$missing" -eq 0

# The recovery tool and the module it imports are in two different packages,
# and the harness unpacks both because an install has both. That is only safe
# because the dependency is declared — otherwise a box could have the tool and
# not the module, in the one situation the tool exists for.
section 'the recovery tool can import what it needs'
check 'the tool is shedos-system'"'"'s' \
    test "$(owns /usr/lib/shedos/emergency-recovery-ui.py)" = shedos-system
check 'apply_core is shedman'"'"'s' \
    test "$(owns /usr/lib/shedos/apply_core.py)" = shedman
bsdtar -xOf "$PKGS"/shedos-system-*.pkg.tar.zst .PKGINFO > "$WORK/sys.pkginfo"
check 'and shedos-system declares the dependency' \
    grep -qx 'depend = shedman' "$WORK/sys.pkginfo"

# --- the kernel wiring, and the package that is not there -------------------

section 'the kernel the release installs'
base_txt=$ROOT/packages/official/base.txt
for pkg in linux-zen linux-zen-headers linux linux-headers; do
    check "base.txt names $pkg" grep -qxF "$pkg" "$base_txt"
done
check 'the released system ships the limine renderer' \
    test -x "$MERGED/usr/lib/shedos/render-limine-config.sh"
check 'and a preset that builds the fallback image' \
    grep -qF "PRESETS=('default' 'fallback')" "$MERGED/etc/mkinitcpio.d/linux-zen.preset"

section 'the retired kernel package is gone from the release'
# The negative assertion the monolith's kernel suite made against a directory.
# The release is the thing that can answer it now: a package nobody publishes
# cannot be pinned, cannot be in the closure, and cannot be on the ISO.
check 'the manifest names no shedos-kernel' \
    bash -c '! grep -q "^name = \"shedos-kernel\"" "$1"' _ "$MANIFEST"
check 'the closure names no shedos-kernel' \
    bash -c '! grep -q "^shedos-kernel" "$1"' _ "$ROOT/packages/.meta-closure.txt"
check 'the package list names no shedos-kernel' \
    bash -c '! grep -qx "shedos-kernel" "$1"' _ "$ROOT/archiso/packages.x86_64"
check 'the metapackage does not depend on it' \
    bash -c '! grep -q "shedos-kernel" "$1"' _ "$ROOT/packaging/shedos-meta/PKGBUILD"

section 'the Secure Boot backends the verbs shell out to'
for pkg in sbctl tpm2-tools systemd-ukify; do
    check "base.txt names $pkg" grep -qxF "$pkg" "$base_txt"
done
sysinfo=$WORK/system.pkginfo
bsdtar -xOf "$PKGS"/shedos-system-*.pkg.tar.zst .PKGINFO > "$sysinfo"
for pkg in sbctl tpm2-tools systemd-ukify; do
    check "the released shedos-system depends on $pkg" \
        grep -qx "depend = $pkg" "$sysinfo"
done
for verb in secureboot tpm2 key encrypt; do
    check "and ships the $verb verb" test -x "$LIBEXEC/$verb"
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if (( fail )); then
    printf '  %s\n' "${failed[@]}" >&2
    exit 1
fi
