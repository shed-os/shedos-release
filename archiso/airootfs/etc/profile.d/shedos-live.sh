#!/bin/bash
# ShedOS Live Environment Profile

# Set environment variables
export EDITOR=nvim
export VISUAL=nvim
export BROWSER=firefox
export TERMINAL=kitty

# XDG Base Directories
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"

# Show welcome message on login
if [ -z "$SHEDOS_WELCOME_SHOWN" ] && [ -t 1 ]; then
    export SHEDOS_WELCOME_SHOWN=1
    echo ""
    echo "  ╔═══════════════════════════════════════════════════════════╗"
    echo "  ║                    Welcome to ShedOS                      ║"
    echo "  ║                                                           ║"
    echo "  ║  To install ShedOS, run:  shedos-installer                ║"
    echo "  ║  For help:                shedos-installer --help         ║"
    echo "  ║                                                           ║"
    echo "  ║  Live user: shedos (passwordless sudo)                    ║"
    echo "  ╚═══════════════════════════════════════════════════════════╝"
    echo ""
fi
