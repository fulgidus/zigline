#!/bin/bash

# Force SDL to use X11 backend for better compatibility with Wayland/KDE
export SDL_VIDEODRIVER=x11

# Run Zigline
cd "$(dirname "$0")"
zig build run "$@"
