# ShedOS Live Environment - Auto-start graphical installer on tty1

# Ensure XDG environment variables are set for application launchers (Walker/elephant)
export XDG_DATA_DIRS="${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

# Only auto-start on tty1 (main console)
if [[ $(tty) == "/dev/tty1" ]]; then
    # Clear screen and show welcome
    clear
    echo ""
    echo "  ╔═══════════════════════════════════════════════════════════╗"
    echo "  ║               Welcome to ShedOS Live                      ║"
    echo "  ║                                                           ║"
    echo "  ║  The graphical installer will start automatically.        ║"
    echo "  ║  Press Ctrl+C within 3 seconds to skip to shell.          ║"
    echo "  ╚═══════════════════════════════════════════════════════════╝"
    echo ""

    # Give user chance to cancel
    sleep 3

    # Launch Hyprland (Wayland compositor) with Calamares
    echo "Starting graphical environment..."
    exec Hyprland
fi
