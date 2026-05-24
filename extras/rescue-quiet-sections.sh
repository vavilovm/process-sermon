#!/bin/bash
# Boost specific quiet sections, then normalize the final sermon MP3.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
# shellcheck source=lib/audio-common.sh
source "$ROOT_DIR/lib/audio-common.sh"

usage() {
  cat <<'USAGE'
Usage:
  ./rescue-quiet-sections.sh AUDIO_FILE --section START-END [--section START-END ...] [options]

Sections use seconds, min:sec, or hour:min:sec.
The selected sections are boosted before final normalization.

Options:
  --section START-END   Quiet part to boost, e.g. 2:10-3:05.
  --boost VALUE         Boost amount, default 8dB.
  --outdir DIR          Folder for the rescued MP3.
  --output FILE         Exact output file path.
  -h, --help            Show this help.

Examples:
  ./rescue-quiet-sections.sh sermon.wav --section 2:10-3:05 --section 21:00-22:15
  ./rescue-quiet-sections.sh sermon.wav --section 2:10-3:05 --boost 12dB

If you run this script with only the audio file, it will ask for sections.
USAGE
}

INPUT=""
OUTDIR=""
OUTPUT=""
BOOST="8dB"
SECTIONS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --section)
      [ -n "${2:-}" ] || audio_die "--section requires START-END"
      SECTIONS+=("$2")
      shift 2
      ;;
    --boost)
      BOOST="${2:-}"
      [ -n "$BOOST" ] || audio_die "--boost requires a value, e.g. 8dB"
      shift 2
      ;;
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

if [ "${#SECTIONS[@]}" -eq 0 ]; then
  echo "Enter quiet sections to boost as START-END, for example 2:10-3:05."
  echo "Press Enter on a blank line when finished."
  while true; do
    read -r -p "Quiet section: " section
    [ -n "$section" ] || break
    SECTIONS+=("$section")
  done
fi

[ "${#SECTIONS[@]}" -gt 0 ] || audio_die "At least one --section is required"

INPUT="$(audio_abs_path "$INPUT")"
[ -n "$OUTDIR" ] || OUTDIR="$(audio_default_outdir_for "$INPUT")"
[ -n "$OUTPUT" ] || OUTPUT="$(audio_default_output "$INPUT" "-quiet-section-rescue" "$OUTDIR")"
mkdir -p "$(dirname "$OUTPUT")"

FILTERS=("highpass=f=80")
for section in "${SECTIONS[@]}"; do
  if [[ "$section" != *-* ]]; then
    audio_die "Invalid section '$section'. Use START-END, e.g. 2:10-3:05."
  fi
  start="${section%-*}"
  end="${section#*-}"
  start_seconds="$(audio_parse_time "$start")"
  end_seconds="$(audio_parse_time "$end")"
  [ "$end_seconds" -gt "$start_seconds" ] || audio_die "Section end must be after start: $section"
  FILTERS+=("volume=volume=${BOOST}:enable='between(t,${start_seconds},${end_seconds})'")
done
FILTERS+=("loudnorm=I=-16:LRA=11:TP=-1.5" "alimiter=limit=0.95")
FILTER="$(audio_join_filters "${FILTERS[@]}")"

echo "Input:    $INPUT"
echo "Boost:    $BOOST"
printf 'Sections: %s\n' "${SECTIONS[*]}"
echo "Output:   $OUTPUT"
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
