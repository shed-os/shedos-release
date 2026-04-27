#!/usr/bin/env bash
# shedOS airootfs customization script — runs inside the chroot during
# mkarchiso pacstrap.
#
# Keep this file LEAN. Anything ShedOS-specific that could be a file in a
# package should live in a package (packaging/shedos-*); things that must
# happen at ISO-build time for the live-boot environment stay here:
#   - locale/timezone
#   - live-user account + SDDM autologin
#   - service enables needed for the live shell (NetworkManager, sddm, …)
#   - mkinitcpio -P (archiso hooks + Plymouth theme picked up by shedos-branding)
#
# NOT here (owned by packages now):
#   - /etc/sudoers.d/wheel              → shedos-system
#   - /etc/sddm.conf.d/theme.conf       → shedos-system
#   - /etc/NetworkManager/conf.d/…      → shedos-system
#   - /etc/skel/**                      → shedos-hyprland / shedos-nvim
#   - shedos-*.service enables          → each package's .install hook

set -euo pipefail

echo "=========================================="
echo "shedOS customize_airootfs.sh STARTING"
echo "=========================================="

# bat ships a Catppuccin theme in /usr/share/bat/themes/ (packaged asset);
# rebuild the cache so it's selectable without per-user setup.
bat cache --build || echo "WARNING: Failed to rebuild bat cache"

# Locale
echo "LANG=en_US.UTF-8" > /etc/locale.conf
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen

# Timezone
ln -sf /usr/share/zoneinfo/UTC /etc/localtime

# Services needed for the live shell
systemctl enable NetworkManager
systemctl enable sddm
systemctl enable bluetooth
systemctl enable iwd
systemctl enable vboxservice.service || true
systemctl enable qemu-guest-agent.service || true

# PipeWire user-scope sockets for every user (live user included).
systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service

# SDDM live autologin. Session= is the filename stem of a .desktop in
# /usr/share/wayland-sessions/. For Hyprland that's "hyprland" — using
# "start-hyprland" (the wrapper binary) makes SDDM fall back to the login
# form silently.
cat > /etc/sddm.conf.d/live-session-autologin.conf <<EOF
[Autologin]
User=shedos
Session=hyprland
Relogin=false
EOF
chmod 644 /etc/sddm.conf.d/live-session-autologin.conf

# Empty passwords for live-session root + shedos user (live ISO only).
echo 'root:' | chpasswd -e
sed -i 's/^root:!/root:/' /etc/shadow

useradd -m -G wheel,video,audio,input,storage -s /usr/bin/zsh shedos 2>/dev/null || true
echo 'shedos:' | chpasswd -e
sed -i 's/^shedos:!/shedos:/' /etc/shadow

# Live user is pre-baked in airootfs/etc/{passwd,shadow,group}, so the
# useradd above no-ops and never copies /etc/skel into /home/shedos.
# Seed the home from /etc/skel manually now that pacstrap has installed
# shedos-hyprland's dotfiles there. Without this the live user gets no
# hyprland.conf / .zshrc and Hyprland boots with the watchdog warning
# (the disable_watchdog_warning = true line lives in /etc/skel/.config/
# hypr/hyprland.conf, not in any airootfs override).
mkdir -p /home/shedos
cp -a /etc/skel/. /home/shedos/
chown -R shedos:shedos /home/shedos

# Calamares ships a sudoers drop-in at install time; fix its mode if present.
[[ -f /etc/sudoers.d/calamares ]] && chmod 440 /etc/sudoers.d/calamares

# Polkit rules shipped by various packages sometimes end up with stricter
# perms than polkit expects — normalize.
chmod 644 /etc/polkit-1/rules.d/*.rules 2>/dev/null || true

# === Free-win cleanup before squashfs build (~1.3 GB savings) ===
# These are bytes pacstrap left behind that the installed system never
# uses. Wipe them now so the squashfs doesn't carry them either.
#
# Pacman cache: pacstrap downloads .pkg.tar.zst into /var/cache/pacman/pkg
# AND unpacks them. The cached archives stay around in the squashfs but
# Calamares' unpackfs-exclude.conf already wipes /var/cache/pacman/pkg/*
# on the install target — they're useless on the installed system.
# Stripping them here removes ~1 GB from the live ISO too. Live-ISO
# `pacman -S` over the network still works; only OFFLINE live-ISO
# `pacman -S` would degrade — which doesn't affect Calamares-driven
# installs at all.
rm -f /var/cache/pacman/pkg/*.pkg.tar.zst* 2>/dev/null || true

# Translated locale data: keep en/en_US/C, drop the rest (~80 MB).
# /usr/lib/locale is glibc-built (already filtered to en_US.UTF-8 by
# `locale-gen` above). /usr/share/locale is per-package translation
# catalogs — most apps will fall back to en cleanly.
find /usr/share/locale -mindepth 1 -maxdepth 1 -type d \
    ! -name 'en' ! -name 'en_US' ! -name 'C' \
    -exec rm -rf {} + 2>/dev/null || true

# Translated man pages: keep $LANG-agnostic man{1..8}; drop man-<lang>/.
find /usr/share/man -mindepth 1 -maxdepth 1 -type d \
    ! -name 'man*' \
    -exec rm -rf {} + 2>/dev/null || true

# Package docs: drop /usr/share/doc/*/{html,examples} and per-package
# translations. Preserve the per-package directory itself for any
# tooling that probes /usr/share/doc/<pkg> existence.
rm -rf /usr/share/doc/*/{html,examples,*-translations} 2>/dev/null || true

# GNU info pages — texinfo readers aren't part of the Hyprland flow.
rm -rf /usr/share/info/*.info* 2>/dev/null || true

# Regenerate initramfs with archiso hooks (and the shedos Plymouth theme,
# which shedos-branding sets as default via its post_install hook).
mkinitcpio -P

# Oh My Zsh is pacstrapped to /usr/share/oh-my-zsh (oh-my-zsh-git).
# Clone it into the live user's home so ~/.zshrc's $ZSH paths work.
# Installed systems get the same treatment via Calamares / shedos-welcome.
if [[ -d /usr/share/oh-my-zsh ]]; then
    cp -r /usr/share/oh-my-zsh /home/shedos/.oh-my-zsh
    mkdir -p /home/shedos/.oh-my-zsh/custom/themes
    ln -sfn /usr/share/zsh-theme-powerlevel10k \
        /home/shedos/.oh-my-zsh/custom/themes/powerlevel10k
    chown -R shedos:shedos /home/shedos/.oh-my-zsh
fi

# go build proxy needs resolv.conf to point at systemd-resolved.
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf 2>/dev/null || true

echo "Customization complete!"
