#!/usr/bin/env bash
# boot-assert.sh — headless proof that an ISO actually boots.
#
#   scripts/boot-assert.sh <iso> [timeout-seconds]
#
# Boots the ISO's own kernel/initramfs directly in QEMU (-kernel /
# -initrd, with the ISO attached so archiso's hook finds the squashfs
# by label) and watches the serial console for systemd reaching
# multi-user. Direct kernel boot lets us append console=ttyS0 without
# modifying the ISO — the shipped boot entries are quiet+splash and
# say nothing on serial.
#
# This is the tag gate ("no ISO ships unbooted"): it catches a broken
# initramfs, a missing/corrupt squashfs, kernel/module mismatches and
# early-userspace regressions. It does not assert the desktop — the
# live session starts Hyprland from autologin, which has no serial
# footprint; the release soak covers that interactively.
#
# KVM is used when /dev/kvm exists (GitHub's Linux runners have it);
# otherwise TCG with a proportionally longer default timeout.

set -uo pipefail

iso=${1:?usage: $0 <iso> [timeout-seconds]}
[[ -f $iso ]] || { echo "boot-assert: no such ISO: $iso" >&2; exit 2; }

# Timeout keyed on /dev/kvm presence; the qemu invocation itself uses
# an accel fallback chain (kvm, then tcg) so a present-but-broken KVM
# node degrades to emulation instead of failing the gate.
if [[ -c /dev/kvm && -w /dev/kvm ]]; then
    accel="kvm"
    # The live ISO spends ~2-3 min in network-wait timeouts under
    # QEMU user-mode networking before multi-user; drilled at ~325s.
    timeout=${2:-600}
else
    accel="tcg"
    timeout=${2:-1800}
    echo "boot-assert: /dev/kvm unavailable; TCG emulation (timeout ${timeout}s)"
fi

work=$(mktemp -d -t boot-assert.XXXXXX)
qemu_pid=""
cleanup() {
    [[ -n $qemu_pid ]] && kill "$qemu_pid" 2>/dev/null
    # bsdtar preserves the ISO's read-only modes; rm needs them writable.
    chmod -R u+w -- "$work" 2>/dev/null
    rm -rf -- "$work"
}
trap cleanup EXIT

label=$(blkid -o value -s LABEL "$iso" 2>/dev/null)
[[ -n $label ]] || { echo "boot-assert: cannot read ISO volume label" >&2; exit 2; }

# The profile owns the on-ISO directory name (install_dir="shedos",
# not archiso's default "arch"). Read it rather than hardcode either.
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
install_dir=$(sed -n 's/^install_dir="\([^"]*\)"$/\1/p' "$here/../archiso/profiledef.sh")
[[ -n $install_dir ]] || {
    echo "boot-assert: cannot read install_dir from archiso/profiledef.sh" >&2
    exit 2
}

# Pull the kernel + initramfs out of the ISO for direct boot. The
# ISO's default menu entry is the linux-zen pair on current images,
# but older releases shipped a single differently-named kernel —
# prefer zen, otherwise accept exactly one vmlinuz-* with its
# matching non-fallback initramfs.
bsdtar -C "$work" -xf "$iso" "$install_dir/boot/x86_64/*" 2>/dev/null
bootdir=$work/$install_dir/boot/x86_64
if [[ -f $bootdir/vmlinuz-linux-zen && -f $bootdir/initramfs-linux-zen.img ]]; then
    kernel=$bootdir/vmlinuz-linux-zen
    initrd=$bootdir/initramfs-linux-zen.img
else
    mapfile -t kernels < <(compgen -G "$bootdir/vmlinuz-*" || true)
    if (( ${#kernels[@]} != 1 )); then
        echo "boot-assert: cannot pick a kernel in the ISO; candidates:" >&2
        printf '  %s
' "${kernels[@]:-none}" >&2
        exit 2
    fi
    kernel=${kernels[0]}
    initrd=$bootdir/initramfs-${kernel##*/vmlinuz-}.img
    [[ -f $initrd ]] || {
        echo "boot-assert: no matching initramfs for $kernel" >&2
        exit 2
    }
fi

serial=$work/serial.log
: > "$serial"

qemu-system-x86_64 \
    -accel kvm -accel tcg \
    -m 4096 -smp 2 \
    -display none -no-reboot \
    -serial "file:$serial" \
    -kernel "$kernel" \
    -initrd "$initrd" \
    -append "archisobasedir=$install_dir archisolabel=$label cow_spacesize=2G console=ttyS0,115200 systemd.journald.forward_to_console=1" \
    -cdrom "$iso" \
    >"$work/qemu.out" 2>&1 &
qemu_pid=$!

echo "boot-assert: booting $iso (label=$label, accel=$accel, timeout=${timeout}s)"

# Verified against what the initramfs actually prints: archiso's hook
# ("device did not show up", "ERROR; Failed to mount", "no root file
# system image found"), mkinitcpio's emergency shell, systemd's
# emergency mode, and kernel panics.
fatal_re='Kernel panic - not syncing|emergency mode|emergency shell|device did not show up|Falling back to interactive prompt|ERROR[;:].*Failed to mount|no root file system image found'

deadline=$(( SECONDS + timeout ))
while (( SECONDS < deadline )); do
    if ! kill -0 "$qemu_pid" 2>/dev/null; then
        echo "boot-assert: QEMU exited prematurely" >&2
        sed 's/^/  qemu: /' "$work/qemu.out" >&2
        tail -40 "$serial" 2>/dev/null | sed 's/^/  serial: /' >&2
        exit 1
    fi
    if grep -aq 'Reached target.*Multi-User System' "$serial"; then
        echo "boot-assert: OK — multi-user reached in ~${SECONDS}s"
        # Best-effort extra signal; absence is not a failure (the
        # desktop autostart has no reliable serial footprint).
        if grep -aqiE 'agetty|autologin|hyprland|uwsm' "$serial"; then
            echo "boot-assert: session activity also visible on console"
        fi
        exit 0
    fi
    if grep -aqE "$fatal_re" "$serial"; then
        echo "boot-assert: FAILED — fatal marker on console" >&2
        grep -anE "$fatal_re" "$serial" | head -5 | sed 's/^/  /' >&2
        tail -40 "$serial" | sed 's/^/  serial: /' >&2
        exit 1
    fi
    sleep 5
done

echo "boot-assert: FAILED — timeout after ${timeout}s without reaching multi-user" >&2
tail -60 "$serial" 2>/dev/null | sed 's/^/  serial: /' >&2
exit 1
