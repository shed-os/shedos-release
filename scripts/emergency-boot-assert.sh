#!/usr/bin/env bash
# End-to-end proof: a missing-disk fstab drops a real ShedOS install to the
# guided tool, and the tool's fix boots it through to multi-user.target.
# Exit 77 = SKIP when a prerequisite is missing (rootless CI has none, and the
# repo doesn't cache an installed image yet):
#   $SHEDOS_EMERGENCY_TEST_IMAGE  installed-ShedOS UEFI qcow2
#   qemu-system-x86_64, qemu-img, OVMF (edk2-ovmf), libguestfs (guestfish)
# Edits go through guestfish (no root, no loop mounts). Serial markers + OVMF
# disk boot follow boot-assert.sh and test-iso.sh:run_qemu_uefi. The limine
# cmdline edit + banner string need re-checking once a base image exists.

set -uo pipefail
SKIP=77

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd -- "$here/.." && pwd)
lib=$repo/packaging/shedos-system/tree/usr/lib/shedos

OVMF_CODE=${SHEDOS_OVMF_CODE:-/usr/share/edk2/x64/OVMF_CODE.4m.fd}
OVMF_VARS=${SHEDOS_OVMF_VARS:-/usr/share/edk2/x64/OVMF_VARS.4m.fd}
base=${SHEDOS_EMERGENCY_TEST_IMAGE:-}

_skip() { echo "emergency-boot-assert: SKIP — $1" >&2; exit "$SKIP"; }

for t in qemu-system-x86_64 qemu-img guestfish; do
    command -v "$t" >/dev/null 2>&1 || _skip "$t not installed"
done
[[ -n $base && -f $base ]] || _skip "set SHEDOS_EMERGENCY_TEST_IMAGE to an installed-ShedOS qcow2"
[[ -f $OVMF_CODE && -f $OVMF_VARS ]] || _skip "OVMF firmware not found (edk2-ovmf)"
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

overlay=$work/disk.qcow2
vars=$work/OVMF_VARS.fd
qemu-img create -f qcow2 -F qcow2 -b "$base" "$overlay" >/dev/null
cp "$OVMF_VARS" "$vars"

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
        -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
        -drive if=pflash,format=raw,file="$vars" \
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

# --- step 1: inject console + the ghost mount; assert the guided tool ---
# fstab edit, host-controlled (download → append → upload).
guestfish --rw -a "$overlay" -i download /etc/fstab "$work/fstab" \
    || _skip "guestfish could not read the image"
printf '%s\n' "$GHOST_LINE" >> "$work/fstab"
guestfish --rw -a "$overlay" -i upload "$work/fstab" /etc/fstab \
    || _skip "guestfish could not write the image"

# limine cmdline edit so the boot is visible on serial (quiet+splash is
# silent). The config Limine boots from can live at the EFI/limine/ subpath
# (primary) or an ESP root, on /boot/efi or /efi — mirror the list in
# apply_core._ESP_LIMINE_MIRRORS. The renderer's directive is
# `kernel_cmdline:`, which the /cmdline:/ address matches as a substring.
guestfish --rw -a "$overlay" -i sh \
  'for f in /boot/efi/EFI/limine/limine.conf /boot/efi/limine.conf /efi/EFI/limine/limine.conf /efi/limine.conf /boot/limine.conf; do [ -f "$f" ] && sed -i "/cmdline:/ s|\$| console=ttyS0,115200 systemd.journald.forward_to_console=1|" "$f"; done; true' \
  || _skip "guestfish could not edit the limine config"

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
