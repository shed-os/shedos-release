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

# Show welcome message on first interactive shell login.
if [ -z "$SHEDOS_WELCOME_SHOWN" ] && [ -t 1 ]; then
    export SHEDOS_WELCOME_SHOWN=1
    echo ""
    echo "  Welcome to ShedOS — a developer-focused Operating System"
    echo ""
    echo "      Website   https://shedos.org"
    echo "      Docs      https://shedos.org/docs"
    echo "      Source    https://github.com/theshedman/shedos"
    echo ""
fi
