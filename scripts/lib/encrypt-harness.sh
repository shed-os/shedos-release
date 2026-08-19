#!/usr/bin/env bash
# Shared machinery for the in-place-encryption QEMU proofs: the prerequisite gate,
# overlay + OVMF setup, an nbd inject of the release's reencryption code with a
# first-boot auto-arm, a QEMU boot helper, and the offline "complete LUKS2" assert.
# Sourced, not run — the caller sets EH_PROG (for messages) and orchestrates. The
# eh_* helpers that hit a missing prerequisite exit 77 (SKIP); nothing else exits.

SKIP=77
_eh_here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd -- "$_eh_here/../.." && pwd)
# The reencryption code is injected out of the published shedos-system, at the
# release the manifest names, rather than out of a working tree: what these
# proofs are about is whether the release encrypts a box in place, and a
# working tree is not the release. eh_setup unpacks it. SHEDOS_SYSTEM_TREE
# points at an unpacked tree instead, for trying a change before publishing it.
tree=${SHEDOS_SYSTEM_TREE:-}

OVMF_CODE=${SHEDOS_OVMF_CODE:-/usr/share/edk2/x64/OVMF_CODE.4m.fd}
OVMF_VARS=${SHEDOS_OVMF_VARS:-/usr/share/edk2/x64/OVMF_VARS.4m.fd}
base=${SHEDOS_ENCRYPT_TEST_IMAGE:-}

arm_timeout=300; enc_timeout=1800
work=""; overlay=""; vars=""
qemu_pid=""; nbd_dev=""; root_mnt=""; esp_mnt=""
eh_luks=0; eh_complete=0

eh_skip() { echo "${EH_PROG:-encrypt-harness}: SKIP — $1" >&2; exit "$SKIP"; }

# Tear down whatever the run left live, in order: qemu, mounts, nbd, the workdir.
# shellcheck disable=SC2329  # invoked via the caller's EXIT trap
eh_cleanup() {
    [[ -n $qemu_pid ]] && kill "$qemu_pid" 2>/dev/null
    [[ -n $esp_mnt ]] && sudo umount "$esp_mnt" 2>/dev/null
    [[ -n $root_mnt ]] && sudo umount "$root_mnt" 2>/dev/null
    [[ -n $nbd_dev ]] && sudo qemu-nbd -d "$nbd_dev" >/dev/null 2>&1
    [[ -n $work ]] && { chmod -R u+w "$work" 2>/dev/null; rm -rf "$work"; }
}

eh_prereqs() {
    local t
    for t in qemu-system-x86_64 qemu-img qemu-nbd cryptsetup; do
        command -v "$t" >/dev/null 2>&1 || eh_skip "$t not installed"
    done
    [[ -n $base && -f $base ]] || eh_skip "set SHEDOS_ENCRYPT_TEST_IMAGE to a plaintext installed-ShedOS qcow2"
    [[ -f $OVMF_CODE && -f $OVMF_VARS ]] || eh_skip "OVMF firmware not found (edk2-ovmf)"
    qemu-system-x86_64 -accel help 2>/dev/null | grep -qiE 'kvm|tcg' || eh_skip "no usable qemu accelerator"
    sudo -n true 2>/dev/null || eh_skip "passwordless sudo required (nbd inject + offline assert run as root)"
}

# A full-disk reencrypt is ~15 min; give it a wide window under KVM, wider on TCG.
eh_set_timeouts() {
    # shellcheck disable=SC2034  # arm_timeout/enc_timeout are read by the sourcing script
    if [[ -c /dev/kvm && -w /dev/kvm ]]; then arm_timeout=300; enc_timeout=1800; else arm_timeout=900; enc_timeout=5400; fi
}

# Prereqs, timeouts, a workdir, and the cleanup trap. Call once, first.
eh_setup() {
    eh_prereqs
    eh_set_timeouts
    work=$(mktemp -d -t encrypt-assert.XXXXXX)
    trap eh_cleanup EXIT
    if [[ -z $tree ]]; then
        tree=$work/shedos-system
        bash "$repo/tools/extract-package.sh" "$repo/release-manifest.toml" \
            shedos-system "$tree" > /dev/null \
            || eh_skip "could not read shedos-system out of the channel"
    fi
    [[ -f $tree/usr/lib/shedos/reencrypt-driver.sh ]] \
        || eh_skip "$tree holds no reencryption driver"
}

# A fresh plaintext overlay (+ writable OVMF vars). Re-callable: a cut disk can't be
# re-cut, so a multi-run caller makes a new overlay per run.
eh_make_overlay() {
    overlay=$work/disk.qcow2; vars=$work/OVMF_VARS.fd
    rm -f "$overlay" "$vars"
    qemu-img create -f qcow2 -F qcow2 -b "$base" "$overlay" >/dev/null \
        || eh_skip "could not create the overlay (is the base a qcow2?)"
    cp "$OVMF_VARS" "$vars"
}

# First /dev/nbd* with size 0 (free).
_eh_free_nbd() {
    local n
    for n in /sys/block/nbd*; do
        [[ -r $n/size ]] || continue
        [[ $(cat "$n/size") -eq 0 ]] && { echo "/dev/${n##*/}"; return 0; }
    done
    return 1
}
eh_connect_nbd() {
    sudo modprobe nbd max_part=16 2>/dev/null || eh_skip "cannot load the nbd kernel module"
    nbd_dev=$(_eh_free_nbd) || eh_skip "no free /dev/nbd* device"
    sudo qemu-nbd -c "$nbd_dev" "$overlay" || eh_skip "qemu-nbd could not connect $nbd_dev"
    sleep 1; sudo partprobe "$nbd_dev" 2>/dev/null; sleep 1
}
eh_disconnect_nbd() {
    [[ -n $nbd_dev ]] && sudo qemu-nbd -d "$nbd_dev" >/dev/null 2>&1
    nbd_dev=""
}

# Mount the overlay's root (@) + ESP, install the release's reencryption code and
# units, enable enrol/finalize, drop a marker-gated first-boot auto-arm, then unmount,
# disconnect, and hand the overlay back to this user (qemu opens it as the user).
eh_inject() {
    eh_connect_nbd
    root_mnt=$work/root; esp_mnt=$work/esp; mkdir -p "$root_mnt" "$esp_mnt"
    sudo mount -o subvol=@ "${nbd_dev}p2" "$root_mnt" || eh_skip "cannot mount the root subvol (not a ShedOS @ layout?)"
    sudo mount "${nbd_dev}p1" "$esp_mnt" || eh_skip "cannot mount the ESP"

    local f s
    for f in usr/lib/shedos/reencrypt-driver.sh usr/lib/shedos/encrypt-enroll.sh \
             usr/lib/shedos/encrypt-reconfigure.sh usr/lib/shedos/encrypt-finalize.sh \
             usr/lib/initcpio/install/shedos-reencrypt usr/libexec/shedman/encrypt \
             usr/libexec/shedman/key; do
        sudo install -Dm755 "$tree/$f" "$root_mnt/$f" || eh_skip "could not inject $f"
    done
    sudo install -Dm644 "$tree/usr/lib/shedos/esp-state.sh" "$root_mnt/usr/lib/shedos/esp-state.sh"
    for s in shedos-reencrypt shedos-encrypt-enroll shedos-encrypt-finalize; do
        sudo install -Dm644 "$tree/usr/lib/systemd/system/$s.service" "$root_mnt/usr/lib/systemd/system/$s.service"
    done
    sudo mkdir -p "$root_mnt/etc/systemd/system/multi-user.target.wants"
    for s in shedos-encrypt-enroll shedos-encrypt-finalize; do
        sudo ln -sf "/usr/lib/systemd/system/$s.service" "$root_mnt/etc/systemd/system/multi-user.target.wants/$s.service"
    done

    # Marker-gated so it arms exactly once.
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
    eh_disconnect_nbd
    sudo chown "$(id -un):$(id -gn)" "$overlay" "$vars" 2>/dev/null
}

eh_boot() {  # $1=serial-log ; backgrounds qemu, sets qemu_pid
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

# Offline ground truth: root is a COMPLETE LUKS2 container — isLuks AND luksDump no
# longer carries an online-reencrypt requirement (the reencrypt finished, not just
# started). Sets eh_luks/eh_complete for the caller's message; returns 0 iff complete.
eh_assert_complete_luks() {
    eh_connect_nbd
    eh_luks=1; eh_complete=1
    sudo cryptsetup isLuks "${nbd_dev}p2" 2>/dev/null || eh_luks=0
    if (( eh_luks )); then
        sudo cryptsetup luksDump --dump-json-metadata "${nbd_dev}p2" 2>/dev/null \
            | grep -q 'online-reencrypt' && eh_complete=0
    fi
    eh_disconnect_nbd
    (( eh_luks && eh_complete ))
}
