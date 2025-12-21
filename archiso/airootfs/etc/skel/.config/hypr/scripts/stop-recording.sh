#!/bin/bash
# shedOS Stop Recording Script

PID_FILE="/tmp/wf-recorder.pid"

if [ ! -f "$PID_FILE" ]; then
    notify-send -u critical "Screen Recording" "No recording in progress"
    exit 1
fi

PID=$(cat "$PID_FILE")

if kill -0 "$PID" 2>/dev/null; then
    kill -INT "$PID"
    rm "$PID_FILE"
    notify-send -u normal "Screen Recording" "Recording stopped and saved to ~/Videos/Recordings/"
else
    rm "$PID_FILE"
    notify-send -u critical "Screen Recording" "Recording process not found"
    exit 1
fi
