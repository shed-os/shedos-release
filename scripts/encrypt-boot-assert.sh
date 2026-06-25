#!/usr/bin/env bash
# End-to-end proof that `shedman encrypt` converts a real install in place: overlay an
# installed-ShedOS image, inject the current working-tree reencryption code, auto-arm on
# first boot, let the offline driver encrypt across a reboot, then assert — offline — that
# the root is a COMPLETE LUKS2 container. This is the slow soak gate behind the T9
# power-cut work, not a CI test: it needs a base image, KVM, and root for the nbd inject.
#
# Scope: arm -> offline encrypt -> root is LUKS2 and the reencrypt finished. Boot-through
# to the desktop and the verify-before-commit flip are proven by hand in QEMU for now;
# wiring them here (a serial handshake plus enrol/finalize assertions) is the next step.
#
# Exit 0 = PASS, 1 = FAIL, 77 = SKIP (a prerequisite is missing):
#   $SHEDOS_ENCRYPT_TEST_IMAGE   plaintext installed-ShedOS UEFI qcow2 (btrfs @ root)
#   qemu-system-x86_64, qemu-img, qemu-nbd, cryptsetup, OVMF (edk2-ovmf)
#   passwordless sudo (the nbd inject and the offline assert run as root)

set -uo pipefail
SKIP=77

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd -- "$here/.." && pwd)
tree=$repo/packaging/shedos-system/tree

OVMF_CODE=${SHEDOS_OVMF_CODE:-/usr/share/edk2/x64/OVMF_CODE.4m.fd}
OVMF_VARS=${SHEDOS_OVMF_VARS:-/usr/share/edk2/x64/OVMF_VARS.4m.fd}
base=${SHEDOS_ENCRYPT_TEST_IMAGE:-}

_skip() { echo "encrypt-boot-assert: SKIP — $1" >&2; exit "$SKIP"; }

for t in qemu-system-x86_64 qemu-img qemu-nbd cryptsetup; do
    command -v "$t" >/dev/null 2>&1 || _skip "$t not installed"
done
[[ -n $base && -f $base ]] || _skip "set SHEDOS_ENCRYPT_TEST_IMAGE to a plaintext installed-ShedOS qcow2"
[[ -f $OVMF_CODE && -f $OVMF_VARS ]] || _skip "OVMF firmware not found (edk2-ovmf)"
qemu-system-x86_64 -accel help 2>/dev/null | grep -qiE 'kvm|tcg' || _skip "no usable qemu accelerator"
sudo -n true 2>/dev/null || _skip "passwordless sudo required (nbd inject + offline assert run as root)"

# A full-disk reencrypt is ~15 min; give it a wide window under KVM, wider on TCG.
if [[ -c /dev/kvm && -w /dev/kvm ]]; then arm_timeout=300; enc_timeout=1800; else arm_timeout=900; enc_timeout=5400; fi

work=$(mktemp -d -t encrypt-assert.XXXXXX)
qemu_pid=""; nbd_dev=""; root_mnt=""; esp_mnt=""
# shellcheck disable=SC2329  # invoked via the EXIT trap
cleanup() {
    [[ -n $qemu_pid ]] && kill "$qemu_pid" 2>/dev/null
    [[ -n $esp_mnt ]] && sudo umount "$esp_mnt" 2>/dev/null
    [[ -n $root_mnt ]] && sudo umount "$root_mnt" 2>/dev/null
    [[ -n $nbd_dev ]] && sudo qemu-nbd -d "$nbd_dev" >/dev/null 2>&1
    chmod -R u+w "$work" 2>/dev/null
    rm -rf "$work"
}
trap cleanup EXIT

overlay=$work/disk.qcow2
vars=$work/OVMF_VARS.fd
qemu-img create -f qcow2 -F qcow2 -b "$base" "$overlay" >/dev/null \
    || _skip "could not create the overlay (is the base a qcow2?)"
cp "$OVMF_VARS" "$vars"

# nbd needs the kernel module and a free device; max_part gives partition nodes.
sudo modprobe nbd max_part=16 2>/dev/null || _skip "cannot load the nbd kernel module"
_free_nbd() {
    local n
    for n in /sys/block/nbd*; do
        [[ -r $n/size ]] || continue
        [[ $(cat "$n/size") -eq 0 ]] && { echo "/dev/${n##*/}"; return 0; }
    done
    return 1
}
_connect_nbd() {
    nbd_dev=$(_free_nbd) || _skip "no free /dev/nbd* device"
    sudo qemu-nbd -c "$nbd_dev" "$overlay" || _skip "qemu-nbd could not connect $nbd_dev"
    sleep 1; sudo partprobe "$nbd_dev" 2>/dev/null; sleep 1
}

# --- inject the working-tree reencryption code + a first-boot auto-arm -------------
_connect_nbd
root_mnt=$work/root; esp_mnt=$work/esp; mkdir -p "$root_mnt" "$esp_mnt"
sudo mount -o subvol=@ "${nbd_dev}p2" "$root_mnt" || _skip "cannot mount the root subvol (not a ShedOS @ layout?)"
sudo mount "${nbd_dev}p1" "$esp_mnt" || _skip "cannot mount the ESP"

for f in usr/lib/shedos/reencrypt-driver.sh usr/lib/shedos/encrypt-enroll.sh \
         usr/lib/shedos/encrypt-reconfigure.sh usr/lib/shedos/encrypt-finalize.sh \
         usr/lib/initcpio/install/shedos-reencrypt usr/libexec/shedman/encrypt \
         usr/libexec/shedman/key; do
    sudo install -Dm755 "$tree/$f" "$root_mnt/$f" || _skip "could not inject $f"
done
sudo install -Dm644 "$tree/usr/lib/shedos/esp-state.sh" "$root_mnt/usr/lib/shedos/esp-state.sh"
for s in shedos-reencrypt shedos-encrypt-enroll shedos-encrypt-finalize; do
    sudo install -Dm644 "$tree/usr/lib/systemd/system/$s.service" "$root_mnt/usr/lib/systemd/system/$s.service"
done
sudo mkdir -p "$root_mnt/etc/systemd/system/multi-user.target.wants"
for s in shedos-encrypt-enroll shedos-encrypt-finalize; do
    sudo ln -sf "/usr/lib/systemd/system/$s.service" "$root_mnt/etc/systemd/system/multi-user.target.wants/$s.service"
done

# Marker-gated so it arms exactly once; copy of out/harness/prep.sh's auto-arm.
sudo install -Dm755 /dev/stdin "$root_mnt/usr/local/bin/harness-autoarm.sh" <<'EOS'
#!/bin/bash
exec >>/var/log/harness-autoarm.log 2>&1
set -x
touch /var/lib/shedos/encrypt-harness-armed
printf 'testpass\ntestpass\n' | shedman encrypt --yes --force-no-ac --no-swap
EOS
sudo install -Dm644 /dev/stdin "$root_mnt/usr/lib/systemd/system/harness-autoarm.service" <<'EOS'
[Unit]
Description=QEMU harness auto-arm shedman encrypt
After=multi-user.target
ConditionPathExists=!/var/lib/shedos/encrypt-harness-armed
[Service]
Type=oneshot
ExecStart=/usr/local/bin/harness-autoarm.sh
[Install]
WantedBy=multi-user.target
EOS
sudo ln -sf /usr/lib/systemd/system/harness-autoarm.service \
    "$root_mnt/etc/systemd/system/multi-user.target.wants/harness-autoarm.service"

sudo umount "$esp_mnt"; esp_mnt=""
sudo umount "$root_mnt"; root_mnt=""
sudo qemu-nbd -d "$nbd_dev" >/dev/null 2>&1; nbd_dev=""
# qemu runs as this user; an overlay the root inject left non-user-owned would not open.
sudo chown "$(id -un):$(id -gn)" "$overlay" "$vars" 2>/dev/null

_boot() {  # $1=serial-log ; backgrounds qemu, sets qemu_pid
    : > "$1"
    qemu-system-x86_64 \
        -accel kvm -accel tcg \
        -m 4096 -smp 2 -machine q35 \
        -display none -no-reboot \
        -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
        -drive if=pflash,format=raw,file="$vars" \
        -drive file="$overlay",format=qcow2,if=virtio \
        -serial "file:$1" \
        >"$work/qemu.out" 2>&1 &
    qemu_pid=$!
}

# --- boot1: auto-arm + reboot; -no-reboot makes QEMU exit on the guest reboot ------
echo "encrypt-boot-assert: boot1 — arming shedman encrypt..."
_boot "$work/boot1.log"
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

# --- boot2: the offline driver encrypts, then the box boots encrypted (no reboot, so
# QEMU will not self-exit) — run the window out, then stop it. The UKI cmdline is
# quiet+splash so this boot is serial-silent; the proof is the offline assert below.
echo "encrypt-boot-assert: boot2 — encrypting offline (up to ${enc_timeout}s)..."
_boot "$work/boot2.log"
deadline=$(( SECONDS + enc_timeout ))
while (( SECONDS < deadline )); do
    kill -0 "$qemu_pid" 2>/dev/null || break   # an early exit means a panic; the assert catches it
    sleep 15
done
kill "$qemu_pid" 2>/dev/null; wait "$qemu_pid" 2>/dev/null; qemu_pid=""

# --- assert (offline, ground truth): root is a COMPLETE LUKS2 container ------------
_connect_nbd
luks=1; complete=1
sudo cryptsetup isLuks "${nbd_dev}p2" 2>/dev/null || luks=0
if (( luks )); then
    sudo cryptsetup luksDump --dump-json-metadata "${nbd_dev}p2" 2>/dev/null \
        | grep -q 'online-reencrypt' && complete=0
fi
sudo qemu-nbd -d "$nbd_dev" >/dev/null 2>&1; nbd_dev=""

if (( luks && complete )); then
    echo "encrypt-boot-assert: PASS — root is a complete LUKS2 container after the offline encrypt"
    exit 0
fi
echo "encrypt-boot-assert: FAILED — root isLuks=$luks reencrypt-complete=$complete" >&2
tail -30 "$work/boot2.log" 2>/dev/null | sed 's/^/  serial: /' >&2
exit 1
