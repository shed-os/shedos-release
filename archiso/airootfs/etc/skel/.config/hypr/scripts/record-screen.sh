#!/bin/bash
# shedOS Screen Recording Script
# Wrapper for wf-recorder with notifications

RECORDINGS_DIR="$HOME/Videos/Recordings"
RECORDING_FILE="$RECORDINGS_DIR/recording_$(date +%Y-%m-%d_%H-%M-%S).mp4"
PID_FILE="/tmp/wf-recorder.pid"

# Create recordings directory if it doesn't exist
mkdir -p "$RECORDINGS_DIR"

# Check if already recording
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        notify-send -u normal "Screen Recording" "Recording already in progress"
        exit 1
    else
        rm "$PID_FILE"
    fi
fi

# Ask user for recording mode
MODE=$(echo -e "Full Screen\nArea Selection\nCancel" | walker -d)

case "$MODE" in
    "Full Screen")
        notify-send -u normal "Screen Recording" "Starting full screen recording..."
        wf-recorder -f "$RECORDING_FILE" &
        echo $! > "$PID_FILE"
        notify-send -u normal "Screen Recording" "Recording started\nPress SUPER+SHIFT+R to stop"
        ;;
    "Area Selection")
        notify-send -u normal "Screen Recording" "Select area to record..."
        GEOMETRY=$(slurp)
        if [ -z "$GEOMETRY" ]; then
            notify-send -u critical "Screen Recording" "Recording cancelled"
            exit 1
        fi
        wf-recorder -g "$GEOMETRY" -f "$RECORDING_FILE" &
        echo $! > "$PID_FILE"
        notify-send -u normal "Screen Recording" "Recording started\nPress SUPER+SHIFT+R to stop"
        ;;
    *)
        notify-send -u low "Screen Recording" "Recording cancelled"
        exit 0
        ;;
esac
