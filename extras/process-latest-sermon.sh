#!/bin/bash
# Find the newest audio file in a folder and process it with process-audio.sh.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
# shellcheck source=lib/audio-common.sh
source "$ROOT_DIR/lib/audio-common.sh"

usage() {
  cat <<'USAGE'
Usage:
  ./extras/process-latest-sermon.sh [FOLDER] [process-audio options]

If FOLDER is omitted, ~/Downloads is used.

Examples:
  ./extras/process-latest-sermon.sh
  ./extras/process-latest-sermon.sh "/Volumes/RECORDER"
  ./extras/process-latest-sermon.sh ~/Downloads --outdir ~/Desktop/Processed
USAGE
}

FOLDER="$HOME/Downloads"

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "$#" -gt 0 ] && [[ "${1:-}" != --* ]]; then
  FOLDER="$1"
  shift
fi

[ -d "$FOLDER" ] || audio_die "Folder does not exist: $FOLDER"
INPUT="$(audio_find_latest "$FOLDER")"

if [ -z "${INPUT:-}" ]; then
  echo "No audio files found in $FOLDER"
  exit 1
fi

exec "$ROOT_DIR/process-audio.sh" "$INPUT" "$@"
