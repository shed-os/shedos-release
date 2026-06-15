#!/usr/bin/env bash
# Build an installed-ShedOS UEFI qcow2 from the live ISO's airootfs squashfs:
# partition a disk, unpack the squashfs as the root, write fstab, install
# Limine via shedos_installer, add a login user, enable the default services.
# The result is what the QEMU boot tests run against.
#
# Built on a raw image via a loop device, then converted to qcow2. qemu-nbd is
# out: the GitHub runners' Azure kernel has no `nbd` module.
#
# Runs as root (loop + chroot). Inputs (env):
#   SHEDOS_ISO             live ISO to pull /shedos/x86_64/airootfs.sfs from
#                          (required unless SHEDOS_AIROOTFS_DIR is set)
#   SHEDOS_AIROOTFS_DIR    alternate rootfs source: a prepared airootfs tree
#   SHEDOS_BASE_IMAGE_OUT  output qcow2 (default ./out/base.qcow2)
#   SHEDOS_BASE_USER       test user (default shedos)
#   SHEDOS_BASE_PASS       test password (default shedos) — CI-internal only
#   SHEDOS_BASE_SIZE       virtual disk size (default 16G)
#   SHEDOS_BASE_AUTOLOGIN  1 = append a greetd [initial_session] so the lock
#                          test can reach the desktop (default 1)
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
iso=${SHEDOS_ISO:-}
airootfs_dir=${SHEDOS_AIROOTFS_DIR:-}
out=${SHEDOS_BASE_IMAGE_OUT:-$repo/out/base.qcow2}
user=${SHEDOS_BASE_USER:-shedos}
pass=${SHEDOS_BASE_PASS:-shedos}
size=${SHEDOS_BASE_SIZE:-16G}
autologin=${SHEDOS_BASE_AUTOLOGIN:-1}

_die() { echo "build-base-image: $1" >&2; exit 1; }
[[ $EUID -eq 0 ]] || _die "must run as root (loop + chroot)"
[[ -n $iso || -n $airootfs_dir ]] || _die "set SHEDOS_ISO or SHEDOS_AIROOTFS_DIR"
for t in qemu-img losetup sgdisk mkfs.btrfs mkfs.fat arch-chroot unsquashfs blkid; do
    command -v "$t" >/dev/null || _die "missing tool: $t"
done
command -v limine >/dev/null || _die "limine not installed on the build host (LimineInstaller needs /usr/share/limine)"

work=$(mktemp -d -t shedos-base.XXXXXX)
mnt=$work/mnt
raw=$work/base.raw
loop=
mkdir -p "$mnt" "$repo/out"

cleanup() {
    set +e
    mountpoint -q "$mnt/boot/efi" && umount "$mnt/boot/efi"
    umount -R "$mnt" 2>/dev/null
    [[ -n $loop ]] && losetup -d "$loop" >/dev/null 2>&1
    rm -rf "$work"
}
trap cleanup EXIT

echo "build-base-image: creating $size disk"
modprobe loop 2>/dev/null || true
qemu-img create -f raw "$raw" "$size" >/dev/null
loop=$(losetup --find --partscan --show "$raw") || _die "losetup failed"

# --- partition: 1G ESP + btrfs root ----------------------------------------
sgdisk -Z "$loop" >/dev/null
sgdisk -n1:0:+1G -t1:ef00 -c1:ESP -n2:0:0 -t2:8300 -c2:shedos "$loop" >/dev/null
partprobe "$loop"
esp_part=${loop}p1
root_part=${loop}p2
# Settle: the partition nodes can lag the partprobe by a beat.
for _ in $(seq 1 20); do [[ -b $esp_part && -b $root_part ]] && break; sleep 0.2; done
[[ -b $esp_part && -b $root_part ]] || _die "partition nodes ${loop}p1/p2 never appeared"

mkfs.fat -F32 -n SHEDOS_ESP "$esp_part" >/dev/null
mkfs.btrfs -f -L shedos "$root_part" >/dev/null

# --- the @/@home subvol layout shedos_limine hardcodes ---------------------
mount "$root_part" "$mnt"
btrfs subvolume create "$mnt/@" >/dev/null
btrfs subvolume create "$mnt/@home" >/dev/null
umount "$mnt"
mount -o subvol=@,compress=zstd "$root_part" "$mnt"
mkdir -p "$mnt/home" "$mnt/boot/efi"
mount -o subvol=@home,compress=zstd "$root_part" "$mnt/home"
mount "$esp_part" "$mnt/boot/efi"

# --- unpack the rootfs -----------------------------------------------------
if [[ -n $iso ]]; then
    echo "build-base-image: extracting airootfs.sfs from $iso"
    xorriso -osirrox on -indev "$iso" \
        -extract /shedos/x86_64/airootfs.sfs "$work/airootfs.sfs" >/dev/null 2>&1 \
        || _die "could not extract airootfs.sfs from the ISO"
    unsquashfs -f -d "$mnt" "$work/airootfs.sfs" >/dev/null
else
    echo "build-base-image: rsyncing $airootfs_dir"
    rsync -aHAX "$airootfs_dir"/ "$mnt"/
fi

# Strip the live-only artifacts Calamares' unpackfs excludes. The file is a
# plain newline list of absolute paths; trailing-slash = directory, and a few
# entries are globs (calamares-*).
while IFS= read -r rel; do
    [[ -z $rel || ${rel:0:1} == "#" ]] && continue
    rel=${rel#/}
    [[ -z $rel ]] && continue              # never rm the mount root
    rm -rf "${mnt:?}/$rel"
done < "$repo/installer/calamares/modules/unpackfs-exclude.conf"

# --- fstab (root + home subvols + ESP with nofail) -------------------------
root_uuid=$(blkid -s UUID -o value "$root_part")
esp_uuid=$(blkid -s UUID -o value "$esp_part")
cat > "$mnt/etc/fstab" <<EOF
UUID=$root_uuid /         btrfs subvol=/@,compress=zstd 0 0
UUID=$root_uuid /home     btrfs subvol=/@home,compress=zstd 0 0
UUID=$esp_uuid  /boot/efi vfat  umask=0077,nofail,x-systemd.device-timeout=5s 0 2
EOF

# --- machine-specific files the unpackfs-exclude stripped ------------------
echo shedos > "$mnt/etc/hostname"
printf 'LANG=en_US.UTF-8\n' > "$mnt/etc/locale.conf"
ln -sf /usr/share/zoneinfo/UTC "$mnt/etc/localtime"
sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' "$mnt/etc/locale.gen" 2>/dev/null || true
arch-chroot "$mnt" locale-gen >/dev/null 2>&1 || true
arch-chroot "$mnt" systemd-machine-id-setup >/dev/null 2>&1 || true

# --- initramfs for the installed kernels, then kernels into /boot ----------
echo "build-base-image: mkinitcpio -P"
arch-chroot "$mnt" mkinitcpio -P >/dev/null 2>&1 \
    || _die "mkinitcpio failed in the target"
# Copy each installed kernel: /usr/lib/modules/<kver>/vmlinuz -> /boot/vmlinuz-<pkgbase>
for pkgbase_file in "$mnt"/usr/lib/modules/*/pkgbase; do
    [[ -f $pkgbase_file ]] || continue
    pkgbase=$(<"$pkgbase_file"); moddir=$(dirname "$pkgbase_file")
    [[ -n $pkgbase && -f $moddir/vmlinuz ]] || continue
    cp "$moddir/vmlinuz" "$mnt/boot/vmlinuz-$pkgbase"
done

# --- install Limine via shedos_installer -----------------------------------
echo "build-base-image: LimineInstaller"
PYTHONPATH="$repo/installer" python3 - "$mnt" "$root_uuid" "$loop" <<'PY'
import sys
from shedos_installer.core.bootloader import LimineInstaller
mount, root_uuid, disk = sys.argv[1:4]
ok = LimineInstaller(mount_point=mount, root_uuid=root_uuid, uefi=True).install(disk)
raise SystemExit(0 if ok else 1)
PY

# --- a login user with a known (CI-internal) password ----------------------
arch-chroot "$mnt" useradd -m -G wheel -s /usr/bin/zsh "$user"
echo "$user:$pass" | arch-chroot "$mnt" chpasswd

# --- enable the shedos_finalize service set --------------------------------
for svc in NetworkManager.service bluetooth.service iwd.service seatd.service \
           greetd.service fstrim.timer postgresql.service docker.service \
           thermald.service; do
    systemctl --root="$mnt" enable "$svc" >/dev/null 2>&1 || true
done

# --- test-only autologin so the lock test reaches the desktop --------------
if [[ $autologin == 1 ]]; then
    cat >> "$mnt/etc/greetd/config.toml" <<EOF

# Added by build-base-image.sh for the lock test (test image only).
[initial_session]
command = "Hyprland"
user = "$user"
EOF
fi

sync
echo "build-base-image: unmounting, detaching loop, converting to qcow2"
umount "$mnt/boot/efi"
umount -R "$mnt"
losetup -d "$loop"; loop=
qemu-img convert -f raw -O qcow2 "$raw" "$out"
sha256sum "$out" | tee "$out.sha256"
echo "build-base-image: wrote $out"
