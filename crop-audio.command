#!/bin/bash
# Double-click launcher for non-technical cropping on macOS.

DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
cd "$DIR" || exit 1

./crop-audio.sh

echo
read -r -p "Press Enter to close this window."
