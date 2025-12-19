#!/usr/bin/env bash
# shedOS live setup script
# Replaces deprecated customize_airootfs.sh

set -e

echo "Starting shedOS live setup..."

# 1. Install Python packages
# Note: In a live ISO, we can use pip. For a permanent install, these should be improved.
if command -v pip &> /dev/null; then
    pip install --break-system-packages pythondialog textual rich || echo "WARNING: pip install failed"
fi

# 2. Locale and Timezone
# (Usually handled by kernel cmdline or separate systemd units, but enforcing here for safety)
if [ ! -f /etc/localtime ]; then
    ln -sf /usr/share/zoneinfo/UTC /etc/localtime
fi
echo "LANG=en_US.UTF-8" > /etc/locale.conf
locale-gen

# 3. User Setup (Impreative)
# We create the user here to ensure groups and shells are correct immediately
if ! id "shedos" &>/dev/null; then
    useradd -m -G wheel,video,audio,input,storage -s /usr/bin/zsh shedos
    # Set empty password
    passwd -d shedos
    passwd -d root
fi

# 4. Permissions
chmod 440 /etc/sudoers.d/wheel
if [ -f /etc/sudoers.d/calamares ]; then
    chmod 440 /etc/sudoers.d/calamares
fi
chmod 644 /etc/polkit-1/rules.d/*.rules 2>/dev/null || true

# 5. Plymouth
if command -v plymouth-set-default-theme &> /dev/null; then
    if [ -d /usr/share/plymouth/themes/shedos ]; then
        plymouth-set-default-theme -R shedos || echo "WARNING: Plymouth theme setup failed"
    fi
fi

# 6. Dotfiles Deployment
# Copy skel files
cp -n /etc/skel/.zshrc /home/shedos/.zshrc 2>/dev/null || true
cp -n /etc/skel/.zprofile /home/shedos/.zprofile 2>/dev/null || true
chown shedos:shedos /home/shedos/.zshrc /home/shedos/.zprofile 2>/dev/null || true

# Oh My Zsh Installation
# We run this as the shedos user
sudo -u shedos bash <<'EOF'
export HOME=/home/shedos
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh" || true
fi

# Plugins and Themes
ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
mkdir -p "$ZSH_CUSTOM/themes" "$ZSH_CUSTOM/plugins"

if [ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]; then
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k" || true
fi

if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions" || true
fi

if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" || true
fi
EOF

# Deploy configs from installer directory to live user
CONFIG_DIR="/opt/shedos-installer/configs"
USER_HOME="/home/shedos"

if [ -d "$CONFIG_DIR" ]; then
    mkdir -p "$USER_HOME/.config"
    mkdir -p "$USER_HOME/.config/hypr"

    # Copy configs
    for config in hyprland waybar kitty mako hyprlock hypridle walker; do
        if [ -d "$CONFIG_DIR/$config" ]; then
            cp -r "$CONFIG_DIR/$config" "$USER_HOME/.config/"
        fi
    done

    # Wallpaper
    if [ -f /opt/shedos-installer/branding/wallpapers/shedos-default.png ]; then
        cp /opt/shedos-installer/branding/wallpapers/shedos-default.png "$USER_HOME/.config/hypr/wallpaper.png"
    fi
    
    # Zsh Configs overrides
    if [ -f "$CONFIG_DIR/system/zshrc" ]; then
        cp "$CONFIG_DIR/system/zshrc" "$USER_HOME/.zshrc"
        cp "$CONFIG_DIR/system/zshrc" "/root/.zshrc"
    fi
    if [ -f "$CONFIG_DIR/system/p10k.zsh" ]; then
        cp "$CONFIG_DIR/system/p10k.zsh" "$USER_HOME/.p10k.zsh"
        cp "$CONFIG_DIR/system/p10k.zsh" "/root/.p10k.zsh"
    fi

    chown -R shedos:shedos "$USER_HOME"
fi

echo "shedOS setup complete."
