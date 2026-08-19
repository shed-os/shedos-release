#!/usr/bin/env bash
# Power-cut soak proof for `shedman encrypt`: an interrupted in-place encrypt must
# resume to a complete LUKS2 container, not a corrupt half-encrypted disk. For each
# cut delay it makes a fresh overlay, arms, starts the offline encrypt, SIGKILLs qemu
# after the delay (the power-cut, mid-encrypt), then boots again and lets the driver
# auto-resume to completion. Slow — each delay is a full ~15-min encrypt. The timed
# cuts cover the early shrink/header window and the long mid-encrypt window by elapsed
# time; the later grow/enrol/flip steps resume idempotently and carry less risk. Cutting
# at a precise window (serial markers + a direct-kernel boot) is a possible refinement.
#
# Exit 0 = PASS, 1 = FAIL, 77 = SKIP. Same prerequisites as encrypt-boot-assert.sh.
# $SHEDOS_ENCRYPT_CUT_DELAYS overrides the cut points (space-separated seconds).

set -uo pipefail
EH_PROG=encrypt-powercut-assert
# shellcheck source=scripts/lib/encrypt-harness.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/encrypt-harness.sh"

eh_setup

# Default: a cut early (shrink/header) and one aimed at the byte-move. enc_timeout is a
# generous ~2x bound, so enc_timeout/4 targets mid-encrypt — but the true encrypt time is
# base-dependent, so tune SHEDOS_ENCRYPT_CUT_DELAYS to land a cut DURING the byte-move
# (time a clean encrypt-boot-assert run first); a cut after the encrypt finishes passes
# without actually testing a mid-encrypt resume.
read -ra delays <<< "${SHEDOS_ENCRYPT_CUT_DELAYS:-25 $(( enc_timeout / 4 ))}"

# boot1: auto-arm + reboot; -no-reboot exits on the guest reboot. Returns 1 on timeout.
_arm() {
    eh_boot "$work/boot1.log"
    local deadline=$(( SECONDS + arm_timeout ))
    while (( SECONDS < deadline )); do
        kill -0 "$qemu_pid" 2>/dev/null || { wait "$qemu_pid" 2>/dev/null; qemu_pid=""; return 0; }
        sleep 5
    done
    kill "$qemu_pid" 2>/dev/null; qemu_pid=""
    return 1
}

# Run qemu until $1 seconds elapse (or it dies early), then SIGKILL — the power-cut.
_run_then_cut() {  # $1=delay-seconds $2=serial-log
    eh_boot "$2"
    local cut_at=$(( SECONDS + $1 ))
    while (( SECONDS < cut_at )); do
        kill -0 "$qemu_pid" 2>/dev/null || break   # died before the cut (a panic)
        sleep 1
    done
    kill -9 "$qemu_pid" 2>/dev/null; wait "$qemu_pid" 2>/dev/null; qemu_pid=""
}

# Boot and let the driver auto-resume to completion, then stop qemu (the box boots
# encrypted and does not reboot, so qemu will not self-exit).
_resume() {  # $1=serial-log
    eh_boot "$1"
    local deadline=$(( SECONDS + enc_timeout ))
    while (( SECONDS < deadline )); do
        kill -0 "$qemu_pid" 2>/dev/null || break
        sleep 15
    done
    kill "$qemu_pid" 2>/dev/null; wait "$qemu_pid" 2>/dev/null; qemu_pid=""
}

for delay in "${delays[@]}"; do
    echo "encrypt-powercut-assert: cut@${delay}s — fresh overlay, arm, encrypt, power-cut, resume..."
    eh_make_overlay
    eh_inject
    if ! _arm; then
        echo "encrypt-powercut-assert: FAILED — cut@${delay}s: boot1 did not arm + reboot within ${arm_timeout}s" >&2
        exit 1
    fi
    _run_then_cut "$delay" "$work/cut-${delay}.log"
    _resume "$work/resume-${delay}.log"
    if eh_assert_complete_luks; then
        echo "encrypt-powercut-assert: cut@${delay}s OK — resumed to a complete LUKS2 container"
    else
        echo "encrypt-powercut-assert: FAILED — cut@${delay}s did not resume to completion (isLuks=$eh_luks complete=$eh_complete)" >&2
        tail -30 "$work/resume-${delay}.log" 2>/dev/null | sed 's/^/  serial: /' >&2
        exit 1
    fi
done

echo "encrypt-powercut-assert: PASS — encrypt resumed to a complete container after a power-cut at every tested delay"
exit 0
