#!/bin/bash
# shedOS First Login - Git Email Configuration
# This script runs once on first login to complete git setup

MARKER_FILE="$HOME/.config/shedos/first-login-done"

# Check if already configured
if [ -f "$MARKER_FILE" ]; then
    exit 0
fi

# Create config directory
mkdir -p "$HOME/.config/shedos"

# Check if git email is already set
GIT_EMAIL=$(git config --global user.email 2>/dev/null)

if [ -z "$GIT_EMAIL" ] || [ "$GIT_EMAIL" == "null" ]; then
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                   Welcome to shedOS!                       ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "To complete your git configuration, please enter your email address."
    echo "This will be used for git commits."
    echo ""
    read -p "Email address: " email

    # Validate email format
    if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        git config --global user.email "$email"
        echo ""
        echo "✓ Git configured successfully!"
        echo "  Name:  $(git config --global user.name)"
        echo "  Email: $email"
        echo ""
    else
        echo ""
        echo "Invalid email format. You can set it later with:"
        echo "  git config --global user.email \"your@email.com\""
        echo ""
    fi

    echo "Press Enter to continue..."
    read
fi

# Mark as done
touch "$MARKER_FILE"
