#!/bin/bash
# Watch a folder for new audio files and process the latest stable file.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
# shellcheck source=lib/audio-common.sh
source "$ROOT_DIR/lib/audio-common.sh"

usage() {
  cat <<'USAGE'
Usage:
  ./extras/watch-audio-folder.sh FOLDER [process-audio options]

This requires fswatch:
  brew install fswatch

Example:
  ./extras/watch-audio-folder.sh "/Volumes/RECORDER"
  ./extras/watch-audio-folder.sh "/Volumes/RECORDER/Recordings" --outdir ~/Desktop/Processed
USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -eq 0 ]; then
  usage
  exit 0
fi

WATCH_FOLDER="$1"
shift

audio_require_command fswatch
audio_require_command ffmpeg

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/process-sermon"
STATE_FILE="$STATE_DIR/processed-files.txt"
LOG_DIR="$HOME/Library/Logs/process-sermon"
mkdir -p "$STATE_DIR"
mkdir -p "$LOG_DIR"
touch "$STATE_FILE"

process_latest_once() {
  local input
  input="$(audio_find_latest "$WATCH_FOLDER")"
  [ -n "${input:-}" ] || return 0
  input="$(audio_abs_path "$input")"

  if grep -Fqx "$input" "$STATE_FILE"; then
    return 0
  fi

  echo "New audio file detected:"
  echo "$input"
  echo "Waiting for copy/recording to finish..."
  audio_notify "New sermon audio detected" "Waiting until the file is ready."
  audio_wait_until_stable "$input"
  echo "Starting processing..."
  "$ROOT_DIR/process-audio.sh" "$input" "$@"
  echo "$input" >> "$STATE_FILE"
  echo "Processing finished."
}

echo "Watching for audio files in: $WATCH_FOLDER"
echo "Watcher log folder: $LOG_DIR"
echo "Press Ctrl-C to stop."
echo

while true; do
  if [ ! -d "$WATCH_FOLDER" ]; then
    echo "Waiting for folder to appear: $WATCH_FOLDER"
    while [ ! -d "$WATCH_FOLDER" ]; do
      sleep 5
    done
    echo "Folder is available: $WATCH_FOLDER"
  fi

  process_latest_once "$@"
  fswatch -1 "$WATCH_FOLDER" >/dev/null || true
done
