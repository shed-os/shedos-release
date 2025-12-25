#!/bin/bash
# Ensure Bluetooth/Audio services are running as requested
systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service
systemctl --user restart pipewire-pulse wireplumber
