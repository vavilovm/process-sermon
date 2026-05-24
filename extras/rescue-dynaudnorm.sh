#!/bin/bash
# Rescue uneven sermon volume with ffmpeg dynaudnorm, then export as MP3.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
# shellcheck source=lib/audio-common.sh
source "$ROOT_DIR/lib/audio-common.sh"

usage() {
  cat <<'USAGE'
Usage:
  ./extras/rescue-dynaudnorm.sh AUDIO_FILE [options]

Options:
  --outdir DIR    Folder for the rescued MP3.
  --output FILE   Exact output file path.
  -h, --help      Show this help.

Example:
  ./extras/rescue-dynaudnorm.sh sermon-with-uneven-volume.wav
USAGE
}

INPUT=""
OUTDIR=""
OUTPUT=""

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
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      audio_die "Unknown option: $1"
      ;;
    *)
      [ -z "$INPUT" ] || audio_die "Only one input file can be processed at a time"
      INPUT="$1"
      shift
      ;;
  esac
done

[ -n "$INPUT" ] || { usage; exit 1; }
[ -f "$INPUT" ] || audio_die "Input file does not exist: $INPUT"
audio_is_audio_file "$INPUT" || audio_die "Unsupported audio file type: $INPUT"
audio_require_command ffmpeg

INPUT="$(audio_abs_path "$INPUT")"
[ -n "$OUTDIR" ] || OUTDIR="$(audio_default_outdir_for "$INPUT")"
[ -n "$OUTPUT" ] || OUTPUT="$(audio_default_output "$INPUT" "-dynaudnorm-rescue" "$OUTDIR")"
mkdir -p "$(dirname "$OUTPUT")"

FILTER="highpass=f=80,dynaudnorm=f=150:g=15:p=0.95:m=10,loudnorm=I=-16:LRA=11:TP=-1.5,alimiter=limit=0.95"

echo "Input:  $INPUT"
echo "Output: $OUTPUT"
echo

ffmpeg -y -hide_banner -i "$INPUT" \
  -af "$FILTER" \
  -ar 44100 \
  -ac 1 \
  -codec:a libmp3lame \
  -b:a 96k \
  "$OUTPUT"

echo
echo "Done:"
echo "$OUTPUT"
