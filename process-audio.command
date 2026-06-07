#!/bin/bash
# Double-click launcher for non-technical sermon processing on macOS.

set -euo pipefail

DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
cd "$DIR" || exit 1

pause_before_close() {
  echo
  read -r -p "Press Enter to close this window."
}

choose_audio_file() {
  if command -v osascript >/dev/null 2>&1; then
    osascript \
      -e 'try' \
      -e 'tell application "Terminal" to activate' \
      -e 'end try' \
      -e 'delay 0.2' \
      -e 'POSIX path of (choose file with prompt "Choose the sermon audio file to process")' 2>/dev/null || return 1
    return 0
  fi

  read -r -p "Path to sermon audio file: " REPLY
  printf '%s\n' "$REPLY"
}

choose_output_folder() {
  if command -v osascript >/dev/null 2>&1; then
    osascript \
      -e 'try' \
      -e 'tell application "Terminal" to activate' \
      -e 'end try' \
      -e 'delay 0.2' \
      -e 'POSIX path of (choose folder with prompt "Choose where to save the processed MP3")' 2>/dev/null || return 1
    return 0
  fi

  read -r -p "Output folder [default: ~/Documents/Processed]: " REPLY
  printf '%s\n' "$REPLY"
}

echo "Process Sermon Audio"
echo

INPUT="$(choose_audio_file || true)"
if [ -z "${INPUT:-}" ]; then
  echo "No audio file selected. Nothing was processed."
  pause_before_close
  exit 0
fi

OUTDIR="$(choose_output_folder || true)"
if [ -z "${OUTDIR:-}" ]; then
  OUTDIR="$HOME/Documents/Processed"
fi

echo
echo "Selected audio:"
echo "$INPUT"
echo
echo "Processed MP3 will be saved in:"
echo "$OUTDIR"
echo
echo "Processing..."
echo

if ./process-audio.sh "$INPUT" --outdir "$OUTDIR"; then
  echo
  echo "Done. Opening the output folder..."
  if command -v open >/dev/null 2>&1; then
    open "$OUTDIR" >/dev/null 2>&1 || true
  fi
else
  echo
  echo "Processing failed. The details above usually explain what went wrong."
fi

pause_before_close
