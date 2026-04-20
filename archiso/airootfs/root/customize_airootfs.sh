#!/usr/bin/env bash
# shedOS airootfs customization script
# This runs inside the chroot during ISO build

set -euo pipefail

echo "=========================================="
echo "shedOS customize_airootfs.sh STARTING"
echo "=========================================="

# Rebuild bat cache. The Catppuccin Mocha theme file is shipped directly in
# the airootfs at /usr/share/bat/themes/ (committed asset, no network needed).
echo "Rebuilding bat cache..."
bat cache --build || echo "WARNING: Failed to rebuild bat cache"

# NOTE: No package caching needed - installer uses rsync to copy live filesystem

# Set default locale
echo "LANG=en_US.UTF-8" > /etc/locale.conf
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen

# Set timezone
ln -sf /usr/share/zoneinfo/UTC /etc/localtime

# Enable services
systemctl enable NetworkManager
systemctl enable sddm
systemctl enable shedos-pacman-init.service || true
systemctl enable vboxservice.service || true
systemctl enable qemu-guest-agent.service || true

# Configure SDDM Theme
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/theme.conf <<EOF
[Theme]
Current=catppuccin-mocha-mauve
EOF

# Configure SDDM Autologin (Live ISO)
# NOTE: Session= is the filename STEM of a .desktop in /usr/share/wayland-sessions/.
# For Hyprland that is `hyprland` (from hyprland.desktop). Do NOT change to
# `start-hyprland` — that's the wrapper binary the .desktop file invokes via
# Exec=, not the session name. Using the wrong value makes SDDM fail silently
# and fall back to the login form.
cat > /etc/sddm.conf.d/live-session-autologin.conf <<EOF
[Autologin]
User=shedos
Session=hyprland
Relogin=false
EOF
chmod 644 /etc/sddm.conf.d/live-session-autologin.conf

# Ensure Zsh is in /etc/shells (Critical for login)
if ! grep -q "/usr/bin/zsh" /etc/shells; then
    echo "/usr/bin/zsh" >> /etc/shells
fi

systemctl enable bluetooth
systemctl enable iwd

# Enable PipeWire and WirePlumber globally for all users
systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service

# Set root to have no password (allows login with empty password)
# Using chpasswd to set empty password properly
echo 'root:' | chpasswd -e
sed -i 's/^root:!/root:/' /etc/shadow

# Create live user
useradd -m -G wheel,video,audio,input,storage -s /usr/bin/zsh shedos 2>/dev/null || true
echo 'shedos:' | chpasswd -e
sed -i 's/^shedos:!/shedos:/' /etc/shadow

# Allow wheel group sudo without password
echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

# Fix permissions on calamares sudoers file
if [ -f /etc/sudoers.d/calamares ]; then
    chmod 440 /etc/sudoers.d/calamares
fi

# Fix permissions on polkit rules
chmod 644 /etc/polkit-1/rules.d/*.rules 2>/dev/null || true

# Configure Plymouth theme
echo "Configuring Plymouth theme..."
if [ -d /usr/share/plymouth/themes/shedos ]; then
    plymouth-set-default-theme -R shedos 2>/dev/null || echo "WARNING: Plymouth theme setup failed"
fi

# Regenerate initramfs with archiso hooks (includes Plymouth)
mkinitcpio -P

# Ensure shedos user home directory has correct ownership
if [ -d /home/shedos ]; then
    chown -R shedos:shedos /home/shedos
fi

# Copy skel files to shedos home if not present
cp -n /etc/skel/.zshrc /home/shedos/.zshrc 2>/dev/null || true
cp -n /etc/skel/.zprofile /home/shedos/.zprofile 2>/dev/null || true
chown shedos:shedos /home/shedos/.zshrc /home/shedos/.zprofile 2>/dev/null || true

# Install Oh My Zsh and Powerlevel10k from system packages (offline-safe).
# The chroot has no network during mkarchiso, so we never `git clone` at build
# time. Sources:
#   - /usr/share/oh-my-zsh           from oh-my-zsh-git (AUR)
#   - /usr/share/zsh-theme-powerlevel10k  from zsh-theme-powerlevel10k-git (AUR)
#   - /usr/share/zsh/plugins/zsh-autosuggestions   from official repos
#   - /usr/share/zsh/plugins/zsh-syntax-highlighting  from official repos
# zsh-autosuggestions + zsh-syntax-highlighting are loaded manually from their
# system paths in ~/.zshrc (not as OMZ custom plugins), so we don't symlink
# them here.
echo "Setting up Oh My Zsh and Powerlevel10k..."

if [ ! -d /usr/share/oh-my-zsh ]; then
    echo "FATAL: /usr/share/oh-my-zsh missing — is oh-my-zsh-git installed?" >&2
    exit 1
fi
if [ ! -d /usr/share/zsh-theme-powerlevel10k ]; then
    echo "FATAL: /usr/share/zsh-theme-powerlevel10k missing — is zsh-theme-powerlevel10k-git installed?" >&2
    exit 1
fi

install_omz_for() {
    local user="$1"
    local home="$2"
    local group="${3:-$user}"

    rm -rf "$home/.oh-my-zsh"
    # Give the user a writable OMZ tree so custom/ can hold symlinks.
    cp -r /usr/share/oh-my-zsh "$home/.oh-my-zsh"
    mkdir -p "$home/.oh-my-zsh/custom/themes"
    ln -sfn /usr/share/zsh-theme-powerlevel10k \
        "$home/.oh-my-zsh/custom/themes/powerlevel10k"
    chown -R "$user:$group" "$home/.oh-my-zsh"
}

install_omz_for shedos /home/shedos
install_omz_for root /root root

echo "Oh My Zsh and Powerlevel10k set up"

# Deploy zsh configurations from /etc/skel
echo "Deploying zsh configurations..."
if [ -f /etc/skel/.zshrc ]; then
    cp /etc/skel/.zshrc /home/shedos/.zshrc
    cp /etc/skel/.zshrc /root/.zshrc
    chown shedos:shedos /home/shedos/.zshrc
fi

if [ -f /etc/skel/.p10k.zsh ]; then
    cp /etc/skel/.p10k.zsh /home/shedos/.p10k.zsh
    cp /etc/skel/.p10k.zsh /root/.p10k.zsh
    chown shedos:shedos /home/shedos/.p10k.zsh
fi

echo "Zsh configurations deployed"

# Deploy desktop configurations from /etc/skel to live user
echo "Deploying desktop configurations..."
if [ -d /etc/skel/.config ]; then
    # Use -n to not overwrite existing files (preserves live user's hyprland.conf with Calamares)
    cp -rn /etc/skel/.config/* /home/shedos/.config/
    
    # Copy wallpaper (force this one)
    if [ -f /opt/shedos-installer/branding/wallpapers/shedos-default.png ]; then
        mkdir -p /home/shedos/.config/hypr
        cp /opt/shedos-installer/branding/wallpapers/shedos-default.png /home/shedos/.config/hypr/wallpaper.png
    fi
    
    # Fix ownership
    chown -R shedos:shedos /home/shedos/.config
    
    echo "Desktop configurations deployed"
else
    echo "WARNING: /etc/skel/.config directory not found"
fi

# Ensure shedos scripts are executable
chmod +x /usr/local/bin/shedos-* 2>/dev/null || true


# Update desktop database to ensure application launchers work
update-desktop-database /usr/share/applications || true

# Resolve DNS issue for go build proxy
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf 2>/dev/null || true

# Create additional directories in the user's home directory - projects, work, and .ssh
# Add to skel so they appear for installed users
mkdir -p /etc/skel/{projects,work,.ssh}
# Add to live user immediately
mkdir -p /home/shedos/{projects,work,.ssh}
chown -R shedos:shedos /home/shedos/{projects,work,.ssh}

echo "Customization complete!"
