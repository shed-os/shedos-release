#!/usr/bin/env bash
# verb-sweep.sh <root>
#
# Every verb, asked on a machine where the whole release is installed.
#
# test/integration asks the same questions of an unpacked tree, and four verbs
# cannot answer there: three declare a Python module the container has not got
# and one execs a path only an install provides. This is the same sweep with
# that excuse removed — <root> is the ISO's airootfs, which is a real install of
# the release with every dependency pacstrapped in.
#
# arch-chroot rather than a bare chroot: it binds /dev, /proc and /sys with
# slave propagation, so an unmount inside cannot reach out and take the host's
# mounts with it.
#
# What a verb answered is its STDOUT. arch-chroot writes its own diagnostics to
# stderr — the airootfs is a directory rather than a mountpoint and it says so
# every single time — and merging the two made every verb look like it had
# printed two lines where the contract says one. Thirty-five verbs, one wrapper,
# and the sweep read the wrapper's voice as theirs.
#
# test/integration merges them on purpose, because there the second stream is
# how a verb that cannot load says which module it wanted. Different question,
# different environment, and neither is wrong for the other.
#
# SHEDOS_CHROOT names the command in place of arch-chroot, which is how the
# cases below run without one.
set -uo pipefail

root=${1:?usage: verb-sweep.sh <root>}
CHROOT=${SHEDOS_CHROOT:-arch-chroot}
[[ -d $root ]] || { echo "verb-sweep: $root does not exist" >&2; exit 2; }
[[ $EUID -eq 0 || -n ${SHEDOS_CHROOT:-} ]] \
    || { echo 'verb-sweep: must be run as root' >&2; exit 1; }
command -v "$CHROOT" > /dev/null \
    || { echo "verb-sweep: $CHROOT is not installed" >&2; exit 2; }

libexec=$root/usr/libexec/shedman
[[ -d $libexec ]] || { echo "verb-sweep: $root installs no verbs" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Exit 2 is "the check could not be made" and exit 1 is "a verb answered
# wrongly". Without this the two are the same number: a chroot that cannot be
# entered fails every verb identically, which reads as thirty-five product
# defects and is one broken wrapper.
if ! "$CHROOT" "$root" /usr/bin/true > /dev/null 2> "$WORK/err"; then
    echo "verb-sweep: could not enter $root" >&2
    sed 's/^/  /' "$WORK/err" >&2
    exit 2
fi

pass=0
fail=0
failed=()

ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s — %s\n' "$1" "$2"; fail=$((fail + 1)); failed+=("$1"); }

# The two answers that are wrong today, in two other repositories, and are
# reported rather than checked less strictly. The same list test/integration
# carries, and it runs in both directions there.
declare -A KNOWN=(
    ['health --help']=1
    ['migrate --complete-fish']=1
)

for tool in "$libexec"/*; do
    verb=$(basename "$tool")
    [[ $verb == _* ]] && continue

    out=$(timeout 60 "$CHROOT" "$root" "/usr/libexec/shedman/$verb" --help-summary 2> "$WORK/err")
    rc=$?
    good=0
    (( rc == 0 )) && [[ -n ${out//[[:space:]]/} ]] && (( $(wc -l <<<"$out") == 1 )) && good=1
    if (( good )); then
        ok "$verb --help-summary"
    else
        bad "$verb --help-summary" "rc=$rc out=${out:0:80} err=$(head -1 "$WORK/err")"
    fi

    out=$(timeout 60 "$CHROOT" "$root" "/usr/libexec/shedman/$verb" --help 2> "$WORK/err")
    rc=$?
    good=0
    (( rc == 0 )) && grep -qiE 'usage|shedman' <<<"$out" && good=1
    if [[ -n ${KNOWN["$verb --help"]:-} ]]; then
        if (( good )); then
            bad "$verb --help is still the reported gap" 'it answers correctly now'
        else
            ok "$verb --help is still the reported gap"
        fi
    elif (( good )); then ok "$verb --help"
    else bad "$verb --help" "rc=$rc out=${out:0:80} err=$(head -1 "$WORK/err")"
    fi

    for mode in --complete-bash --complete-zsh --complete-fish; do
        timeout 60 "$CHROOT" "$root" "/usr/libexec/shedman/$verb" "$mode" > /dev/null 2>&1
        good=$(( $? == 0 ? 1 : 0 ))
        if [[ -n ${KNOWN["$verb $mode"]:-} ]]; then
            if (( good )); then
                bad "$verb $mode is still the reported gap" 'it answers correctly now'
            else
                ok "$verb $mode is still the reported gap"
            fi
        elif (( good )); then ok "$verb $mode"
        else bad "$verb $mode" 'non-zero'
        fi
    done
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if (( fail )); then
    printf '  %s\n' "${failed[@]}" >&2
    exit 1
fi
