#!/bin/bash
# Keep a chosen section from an audio file by entering start and end times.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=lib/audio-common.sh
source "$ROOT_DIR/lib/audio-common.sh"

usage() {
  cat <<'USAGE'
Usage:
  ./crop-audio.sh AUDIO_FILE START_TIME END_TIME [options]

START_TIME and END_TIME are the part you want to keep.
Use seconds, min:sec, or hour:min:sec.

Options:
  --outdir DIR    Folder for the cropped MP3.
  --output FILE   Exact output file path.
  -h, --help      Show this help.

Examples:
  ./crop-audio.sh sermon.wav 1:12 42:30
  ./crop-audio.sh sermon.wav 0:45 1:03:10 --outdir ~/Desktop

If you run this script without arguments, it will ask for the values.
USAGE
}

INPUT=""
START_TIME=""
END_TIME=""
OUTDIR=""
OUTPUT=""

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --outdir)
      OUTDIR="${2:-}"
      [ -n "$OUTDIR" ] || audio_die "--outdir requires a folder"
      shift 2
      ;;
    --output)
      OUTPUT="${2:-}"
      [ -n "$OUTPUT" ] || audio_die "--output requires a file"
      shift 2
      ;;
    -*)
      audio_die "Unknown option: $1"
      ;;
    *)
      if [ -z "$INPUT" ]; then
        INPUT="$1"
      elif [ -z "$START_TIME" ]; then
        START_TIME="$1"
      elif [ -z "$END_TIME" ]; then
        END_TIME="$1"
      else
        audio_die "Unexpected argument: $1"
      fi
      shift
      ;;
  esac
done

if [ -z "$INPUT" ]; then
  read -r -p "Audio file to crop: " INPUT
fi
if [ -z "$START_TIME" ]; then
  read -r -p "Start time to keep, e.g. 1:12: " START_TIME
fi
if [ -z "$END_TIME" ]; then
  read -r -p "End time to keep, e.g. 42:30: " END_TIME
fi

[ -f "$INPUT" ] || audio_die "Input file does not exist: $INPUT"
audio_is_audio_file "$INPUT" || audio_die "Unsupported audio file type: $INPUT"
audio_require_command ffmpeg

INPUT="$(audio_abs_path "$INPUT")"
START_SECONDS="$(audio_parse_time "$START_TIME")"
END_SECONDS="$(audio_parse_time "$END_TIME")"
[ "$END_SECONDS" -gt "$START_SECONDS" ] || audio_die "End time must be after start time"
DURATION=$((END_SECONDS - START_SECONDS))

[ -n "$OUTDIR" ] || OUTDIR="$(audio_default_outdir_for "$INPUT")"
[ -n "$OUTPUT" ] || OUTPUT="$(audio_default_output "$INPUT" "-cropped" "$OUTDIR")"
mkdir -p "$(dirname "$OUTPUT")"

echo "Input:    $INPUT"
echo "Keep:     $START_TIME to $END_TIME"
echo "Output:   $OUTPUT"
echo

ffmpeg -y -hide_banner -ss "$START_SECONDS" -i "$INPUT" \
  -t "$DURATION" \
  -ar 44100 \
  -ac 1 \
  -codec:a libmp3lame \
  -b:a 96k \
  "$OUTPUT"

echo
echo "Done:"
echo "$OUTPUT"
