# ShedOS Live Environment - Auto-start graphical installer on tty1

# Only auto-start on tty1 (main console).
if [[ $(tty) == "/dev/tty1" ]]; then
    clear
    echo ""
    echo "  Welcome to ShedOS Live — the installer starts automatically."
    echo "  Press Ctrl+C within 3 seconds to drop to a shell."
    echo ""
    sleep 3

    # Hyprland isn't running yet, so we can't exec-once the installer from
    # a config. Arm it in the background: wait for Hyprland's IPC socket to
    # appear, then launch Calamares; then hand tty1 to the compositor. The
    # desktop itself comes from /etc/skel (seeded into this home at build),
    # identical to an installed system.
    rt="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    (
        for _ in $(seq 1 60); do
            [ -n "$(ls "$rt"/hypr 2>/dev/null)" ] && break
            sleep 0.5
        done
        exec sudo -E calamares >/tmp/calamares-launch.log 2>&1
    ) &

    echo "Starting graphical environment..."
    exec /usr/lib/shedos/start-hyprland-session.sh
fi
