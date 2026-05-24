#!/bin/bash
# Trim an audio file from a start time, optionally ending at a specific time.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=lib/audio-common.sh
source "$ROOT_DIR/lib/audio-common.sh"

usage() {
  cat <<'USAGE'
Usage:
  ./trim-audio.sh AUDIO_FILE START_TIME [END_TIME] [options]

START_TIME is where the output should begin.
If END_TIME is omitted, the output keeps everything through the original end.
Use seconds, min:sec, or hour:min:sec.

Options:
  --outdir DIR    Folder for the trimmed MP3.
  --output FILE   Exact output file path.
  -h, --help      Show this help.

Examples:
  ./trim-audio.sh sermon.wav 1:12
  ./trim-audio.sh sermon.wav 1:12 42:30
  ./trim-audio.sh sermon.wav 0:45 1:03:10 --outdir ~/Desktop

If you run this script without arguments, it will ask for the values.
USAGE
}

INPUT=""
START_TIME=""
END_TIME=""
OUTDIR=""
OUTPUT=""
INTERACTIVE_PROMPTS=0

if [ "$#" -eq 0 ]; then
  INTERACTIVE_PROMPTS=1
fi

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
if [ -z "$END_TIME" ] && [ "$INTERACTIVE_PROMPTS" -eq 1 ]; then
  read -r -p "End time to keep, or leave blank for original end: " END_TIME
fi

[ -f "$INPUT" ] || audio_die "Input file does not exist: $INPUT"
audio_is_audio_file "$INPUT" || audio_die "Unsupported audio file type: $INPUT"
audio_require_command ffmpeg

INPUT="$(audio_abs_path "$INPUT")"
START_SECONDS="$(audio_parse_time "$START_TIME")"
END_SECONDS=""
DURATION=""
if [ -n "$END_TIME" ]; then
  END_SECONDS="$(audio_parse_time "$END_TIME")"
  [ "$END_SECONDS" -gt "$START_SECONDS" ] || audio_die "End time must be after start time"
  DURATION=$((END_SECONDS - START_SECONDS))
fi

[ -n "$OUTDIR" ] || OUTDIR="$(audio_default_outdir_for "$INPUT")"
[ -n "$OUTPUT" ] || OUTPUT="$(audio_default_output "$INPUT" "-trimmed" "$OUTDIR")"
mkdir -p "$(dirname "$OUTPUT")"

echo "Input:    $INPUT"
if [ -n "$END_TIME" ]; then
  echo "Keep:     $START_TIME to $END_TIME"
else
  echo "Keep:     $START_TIME to original end"
fi
echo "Output:   $OUTPUT"
echo

if [ -n "$DURATION" ]; then
  ffmpeg -y -hide_banner -ss "$START_SECONDS" -i "$INPUT" \
    -t "$DURATION" \
    -ar 44100 \
    -ac 1 \
    -codec:a libmp3lame \
    -b:a 96k \
    "$OUTPUT"
else
  ffmpeg -y -hide_banner -ss "$START_SECONDS" -i "$INPUT" \
    -ar 44100 \
    -ac 1 \
    -codec:a libmp3lame \
    -b:a 96k \
    "$OUTPUT"
fi

echo
echo "Done:"
echo "$OUTPUT"
