#!/usr/bin/env bash
# shedOS airootfs customization script — runs inside the chroot during
# mkarchiso pacstrap.
#
# Live ISO has NO login UI. agetty auto-logs the shedos user into tty1
# (drop-in at /etc/systemd/system/getty@tty1.service.d/autologin.conf),
# /home/shedos/.zprofile then execs Hyprland. Hyprland's exec-once
# chain brings up waybar, wallpaper, nm-applet, and Calamares.

set -euo pipefail

echo "=========================================="
echo "shedOS customize_airootfs.sh STARTING"
echo "=========================================="

# Locale
echo "LANG=en_US.UTF-8" > /etc/locale.conf
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen

# Timezone
ln -sf /usr/share/zoneinfo/UTC /etc/localtime

# Services for the live shell — Wi-Fi (NetworkManager + wpa_supplicant
# default backend) and seatd for Wayland session management.
systemctl enable NetworkManager
systemctl enable seatd

# PipeWire user-scope sockets so the live user gets working audio.
systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service

# Empty passwords for live-session root + shedos user (live ISO only).
echo 'root:' | chpasswd -e
sed -i 's/^root:!/root:/' /etc/shadow

useradd -m -G wheel,video,audio,input,storage -s /usr/bin/zsh shedos 2>/dev/null || true
echo 'shedos:' | chpasswd -e
sed -i 's/^shedos:!/shedos:/' /etc/shadow

# Polkit rules shipped by various packages sometimes end up with stricter
# perms than polkit expects — normalize.
chmod 644 /etc/polkit-1/rules.d/*.rules 2>/dev/null || true

# Squashfs slim-down: drop pacman cache, non-en locales, translated
# man pages, package doc/example dirs, GNU info.
rm -f /var/cache/pacman/pkg/*.pkg.tar.zst* 2>/dev/null || true
find /usr/share/locale -mindepth 1 -maxdepth 1 -type d \
    ! -name 'en' ! -name 'en_US' ! -name 'C' \
    -exec rm -rf {} + 2>/dev/null || true
find /usr/share/man -mindepth 1 -maxdepth 1 -type d \
    ! -name 'man*' \
    -exec rm -rf {} + 2>/dev/null || true
rm -rf /usr/share/doc/*/{html,examples,*-translations} 2>/dev/null || true
rm -rf /usr/share/info/*.info* 2>/dev/null || true

# Regenerate initramfs with archiso hooks (and the shedos Plymouth theme,
# which shedos-branding sets as default via its post_install hook).
mkinitcpio -P

# go build proxy needs resolv.conf to point at systemd-resolved.
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf 2>/dev/null || true

echo "Customization complete!"
