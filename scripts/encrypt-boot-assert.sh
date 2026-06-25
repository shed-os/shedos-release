#!/usr/bin/env bash
# Proof that `shedman encrypt` converts a real install in place: overlay an installed
# image, inject the working-tree reencryption code, auto-arm on first boot, let the
# offline driver encrypt across a reboot, then assert offline that the root is a
# complete LUKS2 container. A slow soak proof, not a CI test — it needs a base image,
# KVM, and root for the nbd inject, and skips cleanly without them.
#
# Exit 0 = PASS, 1 = FAIL, 77 = SKIP (a prerequisite is missing):
#   $SHEDOS_ENCRYPT_TEST_IMAGE   plaintext installed-ShedOS UEFI qcow2 (btrfs @ root)
#   qemu-system-x86_64, qemu-img, qemu-nbd, cryptsetup, OVMF (edk2-ovmf)
#   passwordless sudo (the nbd inject and the offline assert run as root)

set -uo pipefail
EH_PROG=encrypt-boot-assert
# shellcheck source=scripts/lib/encrypt-harness.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/encrypt-harness.sh"

eh_setup
eh_make_overlay
echo "encrypt-boot-assert: injecting reencryption code + auto-arm..."
eh_inject

# boot1: auto-arm + reboot; -no-reboot makes QEMU exit on the guest reboot.
echo "encrypt-boot-assert: boot1 — arming shedman encrypt..."
eh_boot "$work/boot1.log"
deadline=$(( SECONDS + arm_timeout ))
while (( SECONDS < deadline )); do
    kill -0 "$qemu_pid" 2>/dev/null || { wait "$qemu_pid" 2>/dev/null; qemu_pid=""; break; }
    sleep 5
done
if [[ -n $qemu_pid ]]; then
    echo "encrypt-boot-assert: FAILED — boot1 did not arm + reboot within ${arm_timeout}s" >&2
    kill "$qemu_pid" 2>/dev/null; qemu_pid=""
    tail -30 "$work/boot1.log" 2>/dev/null | sed 's/^/  serial: /' >&2
    exit 1
fi
echo "encrypt-boot-assert: boot1 OK — armed and rebooted"

# boot2: the offline driver encrypts, then the box boots encrypted (no reboot, so QEMU
# will not self-exit) — run the window out, then stop it. The boot is serial-silent
# (quiet+splash); the proof is the offline assert.
echo "encrypt-boot-assert: boot2 — encrypting offline (up to ${enc_timeout}s)..."
eh_boot "$work/boot2.log"
deadline=$(( SECONDS + enc_timeout ))
while (( SECONDS < deadline )); do
    kill -0 "$qemu_pid" 2>/dev/null || break   # an early exit means a panic; the assert catches it
    sleep 15
done
kill "$qemu_pid" 2>/dev/null; wait "$qemu_pid" 2>/dev/null; qemu_pid=""

if eh_assert_complete_luks; then
    echo "encrypt-boot-assert: PASS — root is a complete LUKS2 container after the offline encrypt"
    exit 0
fi
echo "encrypt-boot-assert: FAILED — root isLuks=$eh_luks reencrypt-complete=$eh_complete" >&2
tail -30 "$work/boot2.log" 2>/dev/null | sed 's/^/  serial: /' >&2
exit 1
