#!/usr/bin/env bash
# End-to-end proof: a missing-disk fstab drops a real ShedOS install to the
# guided tool, and the tool's fix boots it through to multi-user.target.
# Exit 77 = SKIP when a prerequisite is missing (rootless CI has none, and the
# repo doesn't cache an installed image yet):
#   $SHEDOS_EMERGENCY_TEST_IMAGE  installed-ShedOS UEFI qcow2
#   qemu-system-x86_64, qemu-img, libguestfs (guestfish), binutils (objcopy)
# Edits go through guestfish (no root, no loop mounts). The image boots a UKI
# via Limine, so we extract its kernel+initrd and boot them directly with a
# forced serial console rather than chainloading — the assertion is about fstab
# recovery on the real root, not the bootloader.

set -uo pipefail
SKIP=77

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd -- "$here/.." && pwd)

base=${SHEDOS_EMERGENCY_TEST_IMAGE:-}

_skip() { echo "emergency-boot-assert: SKIP — $1" >&2; exit "$SKIP"; }

for t in qemu-system-x86_64 qemu-img guestfish objcopy; do
    command -v "$t" >/dev/null 2>&1 || _skip "$t not installed"
done

[[ -n $base && -f $base ]] || _skip "set SHEDOS_EMERGENCY_TEST_IMAGE to an installed-ShedOS qcow2"
# qemu-img stores -b relative to the overlay's dir, not $PWD; the overlay lives
# under a mktemp dir, so a relative $base would resolve to a path that isn't there.
base=$(realpath -- "$base")
qemu-system-x86_64 -accel help 2>/dev/null | grep -qiE 'kvm|tcg' || _skip "no usable qemu accelerator"

if [[ -c /dev/kvm && -w /dev/kvm ]]; then timeout=300; else timeout=1200; fi

work=$(mktemp -d -t emergency-assert.XXXXXX)
qemu_pid=""
cleanup() {
    [[ -n $qemu_pid ]] && kill "$qemu_pid" 2>/dev/null
    chmod -R u+w "$work" 2>/dev/null
    rm -rf "$work"
}
trap cleanup EXIT

# The recovery tool comes out of the published packages, at the release the
# manifest names. It used to be read out of a working tree, which proved that
# the working tree recovers a box and said nothing about the release — and this
# runs beside an ISO built out of that release.
#
# Two packages, into one directory, because that is what an install is: the
# tool is shedos-system's and the apply_core it imports is shedman's, which the
# split moved and shedos-system declares a dependency on. Unpacking only the
# one that owns the file gives a /usr/lib/shedos the tool cannot run out of.
# SHEDOS_SYSTEM_TREE points at a prepared tree instead, for the local flow where
# the point is to try a change before it is published.
tree=${SHEDOS_SYSTEM_TREE:-}
if [[ -z $tree ]]; then
    tree=$work/release
    for pkg in shedos-system shedman; do
        bash "$repo/tools/extract-package.sh" "$repo/release-manifest.toml" \
            "$pkg" "$tree" > /dev/null \
            || _skip "could not read $pkg out of the channel"
    done
fi
lib=$tree/usr/lib/shedos
[[ -f $lib/emergency-recovery-ui.py ]] || _skip "$lib holds no emergency-recovery-ui.py"
[[ -f $lib/apply_core.py ]] || _skip "$lib holds no apply_core.py for the tool to import"

overlay=$work/disk.qcow2
qemu-img create -f qcow2 -F qcow2 -b "$base" "$overlay" >/dev/null

# The image boots the default entry's UKI via Limine efi_chainload, so the
# kernel cmdline — including the console= the serial markers ride on — is baked
# into the UKI, not limine.conf. Pull the kernel, initrd, and cmdline out of it
# and boot them directly so we can force ttyS0.
if ! uki=$(guestfish --ro -a "$overlay" -i sh \
    'for f in /boot/limine.conf /boot/efi/EFI/limine/limine.conf /boot/efi/limine.conf /efi/EFI/limine/limine.conf /efi/limine.conf; do [ -f "$f" ] && sed -n "s|^ *image_path: *boot():||p" "$f"; done | head -1'); then
    _skip "guestfish could not open the image (appliance build failed?)"
fi
uki=$(tr -d '\r' <<<"$uki")
[[ -n $uki ]] || _skip "no efi_chainload image_path in limine.conf"
guestfish --ro -a "$overlay" -i download "/boot/efi$uki" "$work/uki.efi" \
    || _skip "could not read the UKI $uki from the image"
objcopy -O binary --only-section=.linux  "$work/uki.efi" "$work/vmlinuz" 2>/dev/null
objcopy -O binary --only-section=.initrd "$work/uki.efi" "$work/initrd"  2>/dev/null
cmdline=$(objcopy -O binary --only-section=.cmdline "$work/uki.efi" /dev/stdout 2>/dev/null | tr -d '\0')
[[ -s $work/vmlinuz && -s $work/initrd && -n $cmdline ]] \
    || _skip "UKI $uki has no extractable kernel/initrd/cmdline"

# A stale UUID that will never appear — its non-nofail mount is what wedges
# boot to emergency.
GHOST_LINE='UUID=00000000-0000-4000-8000-000000000000 /mnt/ghost ext4 defaults 0 2'

_boot() {
    local log=$1
    : > "$log"
    qemu-system-x86_64 \
        -accel kvm -accel tcg \
        -m 4096 -smp 2 -machine q35 \
        -display none -no-reboot \
        -kernel "$work/vmlinuz" -initrd "$work/initrd" \
        -append "$cmdline console=ttyS0,115200 systemd.journald.forward_to_console=1" \
        -drive file="$overlay",format=qcow2,if=virtio \
        -serial "file:$log" \
        >"$work/qemu.out" 2>&1 &
    qemu_pid=$!
}

# Poll the serial log until <success-re>, a kernel panic, QEMU exit, or
# timeout. Returns 0 only on success.
_wait_for() {
    local log=$1 success=$2
    local deadline=$(( SECONDS + timeout ))
    while (( SECONDS < deadline )); do
        if ! kill -0 "$qemu_pid" 2>/dev/null; then return 1; fi
        if grep -aqE "$success" "$log"; then
            kill "$qemu_pid" 2>/dev/null; return 0
        fi
        if grep -aq 'Kernel panic - not syncing' "$log"; then
            kill "$qemu_pid" 2>/dev/null; return 1
        fi
        sleep 5
    done
    kill "$qemu_pid" 2>/dev/null
    return 1
}

# --- step 1: inject the ghost mount; assert we reach the guided tool ---
# fstab edit, host-controlled (download → append → upload).
guestfish --rw -a "$overlay" -i download /etc/fstab "$work/fstab" \
    || _skip "guestfish could not read the image"
printf '%s\n' "$GHOST_LINE" >> "$work/fstab"
guestfish --rw -a "$overlay" -i upload "$work/fstab" /etc/fstab \
    || _skip "guestfish could not write the image"

log1=$work/boot1.log
_boot "$log1"
if _wait_for "$log1" 'ShedOS guided recovery'; then
    echo "emergency-boot-assert: step 1 OK — bad fstab dropped to the guided tool"
else
    echo "emergency-boot-assert: FAILED — never reached the guided recovery tool" >&2
    tail -40 "$log1" 2>/dev/null | sed 's/^/  serial: /' >&2
    exit 1
fi

# --- step 2: apply the tool's REAL fix to the overlay's fstab, offline ---
guestfish --rw -a "$overlay" -i download /etc/fstab "$work/fstab.in" \
    || _skip "guestfish could not read the image (step 2)"
SHEDOS_LIB_ROOT="$lib" python3 - "$lib" "$work/fstab.in" "$work/fstab.out" <<'PY'
import sys, importlib.util
lib, src, dst = sys.argv[1], sys.argv[2], sys.argv[3]
spec = importlib.util.spec_from_file_location("erui", lib + "/emergency-recovery-ui.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
text = open(src).read()
off = m.compute_offerable(text, set())
open(dst, "w").write(m.apply_fix(text, [f.target for f in off]))
PY
guestfish --rw -a "$overlay" -i upload "$work/fstab.out" /etc/fstab \
    || _skip "guestfish could not write the image (step 2)"
echo "emergency-boot-assert: step 2 OK — applied the tool's nofail fix offline"

# --- step 3: boot again; assert the recovered box reaches multi-user ---
log2=$work/boot2.log
_boot "$log2"
if _wait_for "$log2" 'Reached target.*Multi-User System'; then
    echo "emergency-boot-assert: step 3 OK — recovered box reached multi-user.target"
    exit 0
else
    echo "emergency-boot-assert: FAILED — fixed box did not reach multi-user" >&2
    tail -40 "$log2" 2>/dev/null | sed 's/^/  serial: /' >&2
    exit 1
fi
