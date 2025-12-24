#!/bin/bash
# Toggle hyprsunset blue light filter

if pgrep -x "hyprsunset" > /dev/null; then
    pkill -x hyprsunset
    notify-send "Hyprsunset" "Blue light filter disabled" -i video-display
else
    # 4500K is a warm temperature, good for night use
    hyprsunset -t 4500 &
    notify-send "Hyprsunset" "Blue light filter enabled (4500K)" -i video-display
fi
