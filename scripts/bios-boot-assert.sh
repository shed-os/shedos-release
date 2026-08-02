#!/usr/bin/env bash
# bios-boot-assert.sh — headless proof that the ISO boots on BIOS firmware.
#
#   scripts/bios-boot-assert.sh <iso> [timeout-seconds]
#
# boot-assert.sh proves the payload but sidesteps the firmware path by
# direct kernel boot; this boots the full ISO under SeaBIOS, so the
# syslinux config, the BIOS boot images and the loader-to-initramfs
# handoff are what is on trial. Those entries are quiet+splash with no
# serial console, so the boot signal is qemu-guest-agent instead: it
# ships on the live ISO and udev starts it when the virtio port
# appears, so a guest-ping answer means running userspace.
#
# Exit 0 = PASS, 1 = FAIL, 2 = usage, 77 = SKIP (missing prerequisite).

set -uo pipefail

iso=${1:?usage: $0 <iso> [timeout-seconds]}
[[ -f $iso ]] || { echo "bios-boot-assert: no such ISO: $iso" >&2; exit 2; }

for t in qemu-system-x86_64 python3; do
    command -v "$t" >/dev/null 2>&1 \
        || { echo "bios-boot-assert: SKIP — missing $t" >&2; exit 77; }
done

if [[ -c /dev/kvm && -w /dev/kvm ]]; then
    accel="kvm"
    timeout=${2:-600}
else
    accel="tcg"
    timeout=${2:-1800}
    echo "bios-boot-assert: /dev/kvm unavailable; TCG emulation (timeout ${timeout}s)"
fi

work=$(mktemp -d -t bios-boot-assert.XXXXXX)
qemu_pid=""
cleanup() {
    [[ -n $qemu_pid ]] && kill "$qemu_pid" 2>/dev/null
    rm -rf -- "$work"
}
trap cleanup EXIT

qga=$work/qga.sock
serial=$work/serial.log
: > "$serial"

# machine pc, not q35: the older chipset is what real BIOS-era boards
# look like, and it is what test-iso.sh's interactive bios mode uses.
qemu-system-x86_64 \
    -accel kvm -accel tcg \
    -machine pc \
    -m 4096 -smp 2 \
    -display none -no-reboot \
    -serial "file:$serial" \
    -cdrom "$iso" -boot d \
    -device virtio-serial-pci \
    -chardev socket,id=qga0,path="$qga",server=on,wait=off \
    -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0 \
    >"$work/qemu.out" 2>&1 &
qemu_pid=$!

echo "bios-boot-assert: booting $iso (accel=$accel, timeout=${timeout}s)"

_ping() {
    python3 - "$qga" <<'PY'
import socket, sys
s = socket.socket(socket.AF_UNIX)
s.settimeout(4)
try:
    s.connect(sys.argv[1])
    s.sendall(b'{"execute":"guest-ping"}\n')
    sys.exit(0 if b'"return"' in s.recv(4096) else 1)
except OSError:
    sys.exit(1)
PY
}

deadline=$(( SECONDS + timeout ))
while (( SECONDS < deadline )); do
    if ! kill -0 "$qemu_pid" 2>/dev/null; then
        echo "bios-boot-assert: QEMU exited prematurely" >&2
        sed 's/^/  qemu: /' "$work/qemu.out" >&2
        exit 1
    fi
    if _ping; then
        echo "bios-boot-assert: OK — guest agent answered in ~${SECONDS}s"
        exit 0
    fi
    sleep 5
done

echo "bios-boot-assert: FAILED — no guest-agent answer within ${timeout}s" >&2
sed 's/^/  qemu: /' "$work/qemu.out" >&2
tail -20 "$serial" 2>/dev/null | sed 's/^/  serial: /' >&2
exit 1
