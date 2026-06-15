#!/usr/bin/env bash
# End-to-end proof of the passwordless lock, both directions:
#   live      booted from the ISO (/run/archiso present): any keypress
#             returns to the desktop with no password.
#   installed installed to disk (no /run/archiso): a bare keypress is
#             rejected and only the real password unlocks.
# Together these prove the no-auth path keys on /run/archiso and cannot
# leak onto installed systems.
#
# Oracle: the screensaver prints "shedos-screensaver: locked" / "unlocked"
# to stderr -> journald -> serial console (journald.forward_to_console=1).
# We trigger the lock with the real Super+Escape keybind via QEMU's monitor
# (sendkey) and read the markers off serial. No screenshots in the gate.
#
# Inputs (env):
#   SHEDOS_LIVE_ISO          built ShedOS live ISO (runs the live scenario)
#   SHEDOS_INSTALLED_IMAGE   installed-ShedOS qcow2 from build-base-image.sh
#                            (runs the installed scenario)
#   SHEDOS_BASE_PASS         the image's login password (default shedos)
#   SHEDOS_OVMF_CODE/_VARS   OVMF firmware
#
# Exit 77 = SKIP: no KVM (a Wayland desktop under TCG is too slow to gate),
# missing qemu/socat/OVMF, or neither input image set.
set -uo pipefail
SKIP=77

OVMF_CODE=${SHEDOS_OVMF_CODE:-/usr/share/edk2/x64/OVMF_CODE.4m.fd}
OVMF_VARS=${SHEDOS_OVMF_VARS:-/usr/share/edk2/x64/OVMF_VARS.4m.fd}
iso=${SHEDOS_LIVE_ISO:-}
installed=${SHEDOS_INSTALLED_IMAGE:-}
pass=${SHEDOS_BASE_PASS:-shedos}

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd -- "$here/.." && pwd)

_skip() { echo "live-iso-lock-assert: SKIP — $1" >&2; exit "$SKIP"; }
_fail() { echo "live-iso-lock-assert: FAIL — $1" >&2; exit 1; }

[[ -c /dev/kvm && -w /dev/kvm ]] || _skip "no usable KVM (graphical desktop needs it)"
for t in qemu-system-x86_64 socat; do command -v "$t" >/dev/null 2>&1 || _skip "$t not installed"; done
[[ -f $OVMF_CODE && -f $OVMF_VARS ]] || _skip "OVMF firmware not found (edk2-ovmf)"
[[ -n $iso || -n $installed ]] || _skip "set SHEDOS_LIVE_ISO and/or SHEDOS_INSTALLED_IMAGE"

work=$(mktemp -d -t lock-assert.XXXXXX)
# Artifacts live OUTSIDE $work so the cleanup trap can't delete the
# screendumps before CI uploads them.
art=${SHEDOS_LOCK_ARTIFACTS:-$repo/out/lock-artifacts}; mkdir -p "$art"
qemu_pid=""; mon=""; serial=""
cleanup() {
    [[ -n $qemu_pid ]] && kill "$qemu_pid" 2>/dev/null
    chmod -R u+w -- "$work" 2>/dev/null
    rm -rf -- "$work"
}
trap cleanup EXIT

# --- monitor + serial helpers ----------------------------------------------
_mon()  { printf '%s\n' "$1" | socat -T1 - "unix-connect:$mon" >/dev/null 2>&1; }
_key()  { _mon "sendkey $1"; }
# Type an ASCII password one qcode at a time (test creds are simple).
_type() { local s=$1 i c; for (( i=0; i<${#s}; i++ )); do c=${s:i:1}; _key "$c"; sleep 0.05; done; }
_lines() { wc -l < "$serial" 2>/dev/null || echo 0; }
# Wait for <pattern> to appear in serial AFTER line <since>, up to <secs>.
_wait_new() {
    local pat=$1 since=$2 deadline=$(( SECONDS + ${3:-30} ))
    while (( SECONDS < deadline )); do
        kill -0 "$qemu_pid" 2>/dev/null || return 2
        tail -n +"$(( since + 1 ))" "$serial" 2>/dev/null | grep -aq "$pat" && return 0
        sleep 1
    done
    return 1
}

# Drive the real lock keybind (Super+Escape) until the screensaver reports
# locked, polling so we don't depend on a fragile "desktop is up" marker.
_engage_lock() {
    local deadline=$(( SECONDS + 300 )) base
    while (( SECONDS < deadline )); do
        kill -0 "$qemu_pid" 2>/dev/null || return 2
        base=$(_lines)
        _key "meta_l-esc"
        if _wait_new "shedos-screensaver: locked" "$base" 8; then return 0; fi
    done
    return 1
}

_qemu() {  # extra qemu args via "$@"; backgrounds qemu, sets qemu_pid
    mon=$work/mon.sock; serial=$work/serial.log; : > "$serial"
    rm -f "$mon"
    qemu-system-x86_64 \
        -accel kvm -m 4096 -smp 4 -machine q35 \
        -device virtio-gpu-gl-pci -display egl-headless \
        -serial "file:$serial" \
        -monitor "unix:$mon,server,nowait" \
        -no-reboot "$@" >"$work/qemu.out" 2>&1 &
    qemu_pid=$!
    for _ in $(seq 1 50); do [[ -S $mon ]] && break; sleep 0.2; done
}

# ============================ LIVE ========================================
scenario_live() {
    echo "live-iso-lock-assert: [live] booting $iso"
    local label install_dir bootdir kernel initrd
    label=$(blkid -o value -s LABEL "$iso" 2>/dev/null) || true
    install_dir=$(sed -n 's/^install_dir="\([^"]*\)"$/\1/p' "$repo/archiso/profiledef.sh")
    [[ -n $label && -n $install_dir ]] || _fail "[live] cannot read ISO label/install_dir"
    bsdtar -C "$work" -xf "$iso" "$install_dir/boot/x86_64/*" 2>/dev/null
    bootdir=$work/$install_dir/boot/x86_64
    kernel=$bootdir/vmlinuz-linux-zen; initrd=$bootdir/initramfs-linux-zen.img
    [[ -f $kernel && -f $initrd ]] || _fail "[live] kernel/initramfs not found in ISO"

    _qemu \
        -kernel "$kernel" -initrd "$initrd" \
        -append "archisobasedir=$install_dir archisolabel=$label cow_spacesize=2G console=ttyS0,115200 systemd.journald.forward_to_console=1" \
        -cdrom "$iso"

    _engage_lock || { _mon "screendump $art/live-nolock.ppm"; _fail "[live] lock never engaged (desktop never came up?)"; }
    local base; base=$(_lines)
    _key a
    if _wait_new "shedos-screensaver: unlocked" "$base" 30; then
        echo "live-iso-lock-assert: [live] OK — any key unlocked, no password"
    else
        _mon "screendump $art/live-stuck.ppm"
        _fail "[live] a keypress did NOT unlock (no-auth path broken)"
    fi
    kill "$qemu_pid" 2>/dev/null; wait "$qemu_pid" 2>/dev/null; qemu_pid=""
}

# ========================== INSTALLED =====================================
scenario_installed() {
    echo "live-iso-lock-assert: [installed] booting $installed"
    command -v guestfish >/dev/null 2>&1 || _skip "guestfish needed to arm serial on the installed image"
    local overlay vars
    overlay=$work/installed.qcow2; vars=$work/vars.fd
    qemu-img create -f qcow2 -F qcow2 -b "$installed" "$overlay" >/dev/null
    cp "$OVMF_VARS" "$vars"
    # Append console + journald-forward to the Limine cmdline so the markers
    # reach serial (mirrors emergency-boot-assert.sh's limine edit).
    guestfish --rw -a "$overlay" -i sh \
      'for f in /boot/efi/EFI/limine/limine.conf /boot/efi/limine.conf /efi/EFI/limine/limine.conf /efi/limine.conf /boot/limine.conf; do [ -f "$f" ] && sed -i "/cmdline:/ s|$| console=ttyS0,115200 systemd.journald.forward_to_console=1|" "$f"; done; true' \
      || _skip "[installed] guestfish could not arm the image"

    _qemu \
        -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
        -drive if=pflash,format=raw,file="$vars" \
        -drive file="$overlay",format=qcow2,if=virtio

    _engage_lock || { _mon "screendump $art/inst-nolock.ppm"; _fail "[installed] lock never engaged (desktop never came up?)"; }

    # A bare key must NOT unlock.
    local base; base=$(_lines)
    _key a
    if _wait_new "shedos-screensaver: unlocked" "$base" 12; then
        _mon "screendump $art/inst-leaked.ppm"
        _fail "[installed] a bare keypress UNLOCKED — the no-auth path leaked to disk"
    fi
    # The real password must.
    base=$(_lines)
    _type "$pass"; _key ret
    if _wait_new "shedos-screensaver: unlocked" "$base" 30; then
        echo "live-iso-lock-assert: [installed] OK — bare key rejected, password unlocked"
    else
        _mon "screendump $art/inst-noauth.ppm"
        _fail "[installed] the correct password did not unlock"
    fi
    kill "$qemu_pid" 2>/dev/null; wait "$qemu_pid" 2>/dev/null; qemu_pid=""
}

# ============================== run =======================================
ran=0
[[ -n $iso ]]       && { [[ -f $iso ]]       || _skip "SHEDOS_LIVE_ISO not a file"; scenario_live; ran=1; }
[[ -n $installed ]] && { [[ -f $installed ]] || _skip "SHEDOS_INSTALLED_IMAGE not a file"; scenario_installed; ran=1; }
(( ran )) || _skip "nothing to run"
echo "live-iso-lock-assert: PASS"
