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
    (
        # uwsm runs the session and imports its environment into the systemd
        # user manager; DISPLAY lands there once XWayland is up. Adopt it, let
        # root reach the X server, then launch the installer under -platform
        # xcb — the same recipe as shedos-install.desktop. A bare `sudo -E
        # calamares` used to inherit the env directly, but under uwsm the login
        # shell never sees DISPLAY, so calamares started blind and died.
        disp=
        for _ in $(seq 1 120); do
            disp=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^DISPLAY=//p')
            [ -n "$disp" ] && break
            sleep 0.5
        done
        [ -n "$disp" ] && export DISPLAY="$disp"
        xhost +SI:localuser:root >/dev/null 2>&1
        exec sudo -E QT_QPA_PLATFORM=xcb calamares >/tmp/calamares-launch.log 2>&1
    ) &

    echo "Starting graphical environment..."
    exec /usr/lib/shedos/start-hyprland-session.sh
fi
