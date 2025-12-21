#!/bin/bash
# Check if Caps Lock is on

if xset q 2>/dev/null | grep "Caps Lock:.*on" > /dev/null; then
    echo " CAPS LOCK IS ON"
else
    echo ""
fi
