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
set -uo pipefail

root=${1:?usage: verb-sweep.sh <root>}
[[ -d $root ]] || { echo "verb-sweep: $root does not exist" >&2; exit 2; }
[[ $EUID -eq 0 ]] || { echo 'verb-sweep: must be run as root' >&2; exit 1; }
command -v arch-chroot > /dev/null || { echo 'verb-sweep: arch-chroot is not installed' >&2; exit 2; }

libexec=$root/usr/libexec/shedman
[[ -d $libexec ]] || { echo "verb-sweep: $root installs no verbs" >&2; exit 1; }

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

    out=$(timeout 60 arch-chroot "$root" "/usr/libexec/shedman/$verb" --help-summary 2>&1)
    rc=$?
    good=0
    (( rc == 0 )) && [[ -n ${out//[[:space:]]/} ]] && (( $(wc -l <<<"$out") == 1 )) && good=1
    if (( good )); then ok "$verb --help-summary"; else bad "$verb --help-summary" "rc=$rc ${out:0:120}"; fi

    out=$(timeout 60 arch-chroot "$root" "/usr/libexec/shedman/$verb" --help 2>&1)
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
    else bad "$verb --help" "rc=$rc ${out:0:120}"
    fi

    for mode in --complete-bash --complete-zsh --complete-fish; do
        timeout 60 arch-chroot "$root" "/usr/libexec/shedman/$verb" "$mode" > /dev/null 2>&1
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
