#!/usr/bin/env bash
# shedOS airootfs customization script
# This runs inside the chroot during ISO build

echo "=========================================="
echo "shedOS customize_airootfs.sh STARTING"
echo "=========================================="

# Install Python packages via pip (not in Arch repos)
echo "Installing Python packages..."
pip install --break-system-packages pythondialog textual rich || echo "WARNING: pip install failed"

# Install NPM packages globally
echo "Installing global NPM packages..."
npm install -g @angular/language-server typescript-svelte-plugin @vue/language-server || echo "WARNING: npm install failed"

# NOTE: No package caching needed - installer uses rsync to copy live filesystem

# Set default locale
echo "LANG=en_US.UTF-8" > /etc/locale.conf
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen

# Set timezone
ln -sf /usr/share/zoneinfo/UTC /etc/localtime

# Enable services
systemctl enable NetworkManager
systemctl enable sshd
systemctl enable greetd
systemctl enable bluetooth
systemctl enable iwd

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

# Install Oh My Zsh and Powerlevel10k
echo "Installing Oh My Zsh and Powerlevel10k..."

# Install Oh My Zsh for shedos user
sudo -u shedos bash <<'EOF'
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh" || echo "WARNING: Oh My Zsh installation failed"
fi

# Install Powerlevel10k theme
if [ ! -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]; then
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" || echo "WARNING: Powerlevel10k installation failed"
fi

# Install zsh-autosuggestions plugin
if [ ! -d "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ]; then
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" || echo "WARNING: zsh-autosuggestions installation failed"
fi

# Install zsh-syntax-highlighting plugin
if [ ! -d "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" ]; then
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" || echo "WARNING: zsh-syntax-highlighting installation failed"
fi
EOF

# Install Oh My Zsh for root user
if [ ! -d /root/.oh-my-zsh ]; then
    git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git /root/.oh-my-zsh || echo "WARNING: Oh My Zsh installation for root failed"
fi

# Install Powerlevel10k theme for root
if [ ! -d /root/.oh-my-zsh/custom/themes/powerlevel10k ]; then
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git /root/.oh-my-zsh/custom/themes/powerlevel10k || echo "WARNING: Powerlevel10k installation for root failed"
fi

# Install zsh plugins for root
if [ ! -d /root/.oh-my-zsh/custom/plugins/zsh-autosuggestions ]; then
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions /root/.oh-my-zsh/custom/plugins/zsh-autosuggestions || echo "WARNING: zsh-autosuggestions installation for root failed"
fi

if [ ! -d /root/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting ]; then
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git /root/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting || echo "WARNING: zsh-syntax-highlighting installation for root failed"
fi

echo "Oh My Zsh and Powerlevel10k installed"

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

echo "Customization complete!"
