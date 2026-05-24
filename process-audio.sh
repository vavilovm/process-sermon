#!/bin/bash
# Process one sermon audio file into a mono MP3 with dynamic volume normalization.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=lib/audio-common.sh
source "$ROOT_DIR/lib/audio-common.sh"

usage() {
  cat <<'USAGE'
Usage:
  ./process-audio.sh AUDIO_FILE [options]

Options:
  --outdir DIR              Folder for the processed MP3.
  --output FILE             Exact output file path.
  --start TIME              Keep audio starting at TIME.
  --end TIME                Keep audio until TIME. If omitted with --start, keep through the end.
  --interactive-trim        Ask whether to trim the audio.
  --no-trim                 Do not trim manually or by silence detection.
  --no-trim-silence         Do not trim start/end silence.
  --trim-threshold VALUE    Silence threshold, default -60dB.
  --trim-start-duration N   Start silence duration in seconds, default 1.
  --trim-end-duration N     End silence duration in seconds, default 2.
  --max-auto-trim N         Max seconds to auto-trim from either edge, default 300.
  --raw-pcm-rate N          Sample rate for headerless WAV recovery, default 44100.
  --raw-pcm-channels N      Channel count for headerless WAV recovery, default 2.
  --log FILE                Exact log file path.
  -h, --help                Show this help.

Examples:
  ./process-audio.sh ~/Downloads/sermon.wav
  ./process-audio.sh ~/Downloads/sermon.wav --outdir ~/Desktop/Processed
  ./process-audio.sh ~/Downloads/sermon.wav --start 1:12 --end 42:30
  ./process-audio.sh ~/Downloads/sermon.wav --no-trim
  ./process-audio.sh ~/Downloads/sermon.wav --no-trim-silence
USAGE
}

INPUT=""
OUTDIR=""
OUTPUT=""
LOG=""
MANUAL_TRIM=0
MANUAL_START_TIME=""
MANUAL_END_TIME=""
INTERACTIVE_TRIM=0
NO_TRIM=0
TRIM_SILENCE=1
TRIM_THRESHOLD="-60dB"
TRIM_START_DURATION="1"
TRIM_END_DURATION="2"
MAX_AUTO_TRIM="300"
RAW_PCM_RATE="44100"
RAW_PCM_CHANNELS="2"

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
    --log)
      LOG="${2:-}"
      [ -n "$LOG" ] || audio_die "--log requires a file"
      shift 2
      ;;
    --start)
      MANUAL_START_TIME="${2:-}"
      [ -n "$MANUAL_START_TIME" ] || audio_die "--start requires a time"
      MANUAL_TRIM=1
      shift 2
      ;;
    --end)
      MANUAL_END_TIME="${2:-}"
      [ -n "$MANUAL_END_TIME" ] || audio_die "--end requires a time"
      MANUAL_TRIM=1
      shift 2
      ;;
    --interactive-trim)
      INTERACTIVE_TRIM=1
      shift
      ;;
    --no-trim)
      NO_TRIM=1
      TRIM_SILENCE=0
      shift
      ;;
    --no-trim-silence)
      TRIM_SILENCE=0
      shift
      ;;
    --trim-threshold)
      TRIM_THRESHOLD="${2:-}"
      [ -n "$TRIM_THRESHOLD" ] || audio_die "--trim-threshold requires a value"
      shift 2
      ;;
    --trim-start-duration)
      TRIM_START_DURATION="${2:-}"
      [ -n "$TRIM_START_DURATION" ] || audio_die "--trim-start-duration requires seconds"
      shift 2
      ;;
    --trim-end-duration)
      TRIM_END_DURATION="${2:-}"
      [ -n "$TRIM_END_DURATION" ] || audio_die "--trim-end-duration requires seconds"
      shift 2
      ;;
    --max-auto-trim)
      MAX_AUTO_TRIM="${2:-}"
      [ -n "$MAX_AUTO_TRIM" ] || audio_die "--max-auto-trim requires seconds"
      shift 2
      ;;
    --raw-pcm-rate)
      RAW_PCM_RATE="${2:-}"
      [ -n "$RAW_PCM_RATE" ] || audio_die "--raw-pcm-rate requires a sample rate"
      shift 2
      ;;
    --raw-pcm-channels)
      RAW_PCM_CHANNELS="${2:-}"
      [ -n "$RAW_PCM_CHANNELS" ] || audio_die "--raw-pcm-channels requires a channel count"
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
audio_require_command ffprobe

if [ "$NO_TRIM" -eq 1 ] && { [ "$MANUAL_TRIM" -eq 1 ] || [ "$INTERACTIVE_TRIM" -eq 1 ]; }; then
  audio_die "--no-trim cannot be combined with --start, --end, or --interactive-trim"
fi

INPUT="$(audio_abs_path "$INPUT")"
[ -n "$OUTDIR" ] || OUTDIR="$(audio_default_outdir_for "$INPUT")"
[ -n "$OUTPUT" ] || OUTPUT="$(audio_default_output "$INPUT" "-processed" "$OUTDIR")"
[ -n "$LOG" ] || LOG="${OUTPUT%.*}.log"

mkdir -p "$(dirname "$OUTPUT")"
mkdir -p "$(dirname "$LOG")"
: > "$LOG"

RUN_STARTED="$(date '+%Y-%m-%d %H:%M:%S')"
FFPROBE_INPUT_ARGS=()
FFMPEG_INPUT_ARGS=()
INPUT_FORMAT_NOTE="container"
INPUT_PROBE_WARNING=""
MANUAL_START_SECONDS="0"
MANUAL_END_SECONDS=""
MANUAL_SECTION_END=""
MANUAL_SECTION_DURATION=""

log_line() {
  if [ "$#" -eq 0 ]; then
    echo | tee -a "$LOG"
  else
    echo "$*" | tee -a "$LOG"
  fi
}

on_error() {
  local status=$?
  if [ -n "${INPUT_PROBE_WARNING:-}" ]; then
    log_line
    log_line "Probe warning:"
    log_line "$INPUT_PROBE_WARNING"
  fi
  log_line
  log_line "Failed:"
  log_line "$INPUT"
  log_line
  log_line "Log:"
  log_line "$LOG"
  exit "$status"
}

trap on_error ERR

has_wave_header() {
  head -c 12 "$INPUT" | LC_ALL=C grep -q '^RIFF....WAVE'
}

is_wav_filename() {
  local lower
  lower="$(printf '%s\n' "$INPUT" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    *.wav) return 0 ;;
    *) return 1 ;;
  esac
}

configure_input_format() {
  local probe_error
  local channel_layout
  probe_error="$(mktemp "${TMPDIR:-/tmp}/process-sermon-probe.XXXXXX")"

  if ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT" >/dev/null 2>"$probe_error"; then
    rm -f "$probe_error"
    return 0
  fi

  INPUT_PROBE_WARNING="$(cat "$probe_error")"
  rm -f "$probe_error"

  if is_wav_filename && ! has_wave_header; then
    case "$RAW_PCM_CHANNELS" in
      1) channel_layout="mono" ;;
      2) channel_layout="stereo" ;;
      *) channel_layout="" ;;
    esac

    if [ -n "$channel_layout" ] && ffprobe -v error -f s16le -ar "$RAW_PCM_RATE" -ch_layout "$channel_layout" -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT" >/dev/null 2>&1; then
      FFPROBE_INPUT_ARGS=(-f s16le -ar "$RAW_PCM_RATE" -ch_layout "$channel_layout")
      FFMPEG_INPUT_ARGS=(-f s16le -ar "$RAW_PCM_RATE" -ac "$RAW_PCM_CHANNELS")
      INPUT_FORMAT_NOTE="raw PCM fallback: signed 16-bit little-endian, ${RAW_PCM_RATE} Hz, ${RAW_PCM_CHANNELS} channel(s)"
      return 0
    fi
  fi

  if [ -n "$INPUT_PROBE_WARNING" ]; then
    printf '%s\n' "$INPUT_PROBE_WARNING" >&2
  fi
  return 1
}

ask_interactive_trim() {
  local answer

  echo
  read -r -p "Do you want to trim the audio? [y/N] " answer
  case "$answer" in
    y|Y|yes|YES|Yes)
      MANUAL_TRIM=1
      read -r -p "Start time to keep [default: 0:00]: " MANUAL_START_TIME
      read -r -p "End time to keep [blank: original end]: " MANUAL_END_TIME
      [ -n "$MANUAL_START_TIME" ] || MANUAL_START_TIME="0"
      ;;
    *)
      MANUAL_TRIM=0
      MANUAL_START_TIME=""
      MANUAL_END_TIME=""
      ;;
  esac
}

probe_duration() {
  if [ "${#FFPROBE_INPUT_ARGS[@]}" -gt 0 ]; then
    ffprobe -v error "${FFPROBE_INPUT_ARGS[@]}" -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT"
  else
    ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT"
  fi
}

detect_edge_trim() {
  local detect_log="$1"
  local duration="$2"
  local detect_duration
  local silence_filter
  local filters=()

  detect_duration="$(awk -v start_seconds="$TRIM_START_DURATION" -v end_seconds="$TRIM_END_DURATION" 'BEGIN { print (start_seconds < end_seconds ? start_seconds : end_seconds) }')"
  silence_filter="silencedetect=noise=${TRIM_THRESHOLD}:d=${detect_duration}"
  if [ "$MANUAL_TRIM" -eq 1 ]; then
    if [ -n "$MANUAL_END_SECONDS" ]; then
      filters=("atrim=start=${MANUAL_START_SECONDS}:end=${MANUAL_END_SECONDS}" "asetpts=PTS-STARTPTS" "$silence_filter")
    else
      filters=("atrim=start=${MANUAL_START_SECONDS}" "asetpts=PTS-STARTPTS" "$silence_filter")
    fi
  else
    filters=("$silence_filter")
  fi

  if [ "${#FFMPEG_INPUT_ARGS[@]}" -gt 0 ]; then
    ffmpeg -hide_banner -nostats "${FFMPEG_INPUT_ARGS[@]}" -i "$INPUT" \
      -af "$(audio_join_filters "${filters[@]}")" \
      -f null - > "$detect_log" 2>&1
  else
    ffmpeg -hide_banner -nostats -i "$INPUT" \
      -af "$(audio_join_filters "${filters[@]}")" \
      -f null - > "$detect_log" 2>&1
  fi

  awk -v duration="$duration" -v max_trim="$MAX_AUTO_TRIM" -v start_min="$TRIM_START_DURATION" -v end_min="$TRIM_END_DURATION" '
    BEGIN {
      eps = 0.25
      lead = ""
      end = duration + 0
      first_start = ""
      pending_start = ""
    }
    /silence_start:/ {
      value = $0
      sub(/^.*silence_start: /, "", value)
      sub(/ .*/, "", value)
      pending_start = value + 0
      if (first_start == "") {
        first_start = pending_start
      }
    }
    /silence_end:/ {
      value = $0
      sub(/^.*silence_end: /, "", value)
      sub(/ .*/, "", value)
      silence_end = value + 0
      silence_duration = silence_end - pending_start
      if (first_start != "" && first_start <= eps && lead == "" && silence_duration >= start_min) {
        lead = silence_end
      }
      if (pending_start != "" && silence_end >= duration - eps && silence_duration >= end_min) {
        end = pending_start
      }
      pending_start = ""
    }
    END {
      if (pending_start != "") {
        silence_duration = duration - pending_start
        if (first_start != "" && first_start <= eps && lead == "" && silence_duration >= start_min) {
          lead = duration
        }
        if (silence_duration >= end_min) {
          end = pending_start
        }
      }
      if (lead == "") {
        lead = 0
      }

      trim_end = duration - end
      start_warn = 0
      end_warn = 0

      if (lead > max_trim) {
        lead = 0
        start_warn = 1
      }
      if (trim_end > max_trim) {
        end = duration
        end_warn = 1
      }
      if (end <= lead) {
        lead = 0
        end = duration
        start_warn = 2
        end_warn = 2
      }

      printf "%.3f %.3f %d %d\n", lead, end, start_warn, end_warn
    }
  ' "$detect_log"
}

INPUT_DURATION=""
TRIM_START="0"
TRIM_END=""
TRIM_START_WARN=0
TRIM_END_WARN=0
TRIMMED_END_SECONDS="0"
OUTPUT_DURATION=""

configure_input_format
INPUT_DURATION="$(probe_duration)"

if [ "$INTERACTIVE_TRIM" -eq 1 ]; then
  ask_interactive_trim
fi

if [ "$MANUAL_TRIM" -eq 1 ]; then
  [ -n "$MANUAL_START_TIME" ] || MANUAL_START_TIME="0"
  MANUAL_START_SECONDS="$(audio_parse_time "$MANUAL_START_TIME")"
  if [ -n "$MANUAL_END_TIME" ]; then
    MANUAL_END_SECONDS="$(audio_parse_time "$MANUAL_END_TIME")"
    [ "$MANUAL_END_SECONDS" -gt "$MANUAL_START_SECONDS" ] || audio_die "End time must be after start time"
  fi

  awk -v start="$MANUAL_START_SECONDS" -v duration="$INPUT_DURATION" 'BEGIN { exit(start < duration ? 0 : 1) }' \
    || audio_die "Start time must be before the end of the audio"
  if [ -n "$MANUAL_END_SECONDS" ]; then
    awk -v end="$MANUAL_END_SECONDS" -v duration="$INPUT_DURATION" 'BEGIN { exit(end <= duration ? 0 : 1) }' \
      || audio_die "End time must not be after the end of the audio"
  fi

  MANUAL_SECTION_END="${MANUAL_END_SECONDS:-$INPUT_DURATION}"
  MANUAL_SECTION_DURATION="$(awk -v start="$MANUAL_START_SECONDS" -v end="$MANUAL_SECTION_END" 'BEGIN { printf "%.3f", end - start }')"
else
  MANUAL_SECTION_END="$INPUT_DURATION"
  MANUAL_SECTION_DURATION="$INPUT_DURATION"
fi

if [ "$TRIM_SILENCE" -eq 1 ]; then
  DETECT_LOG="$(mktemp "${TMPDIR:-/tmp}/process-sermon-silence.XXXXXX")"
  read -r TRIM_START TRIM_END TRIM_START_WARN TRIM_END_WARN < <(detect_edge_trim "$DETECT_LOG" "$MANUAL_SECTION_DURATION")
  TRIMMED_END_SECONDS="$(awk -v duration="$MANUAL_SECTION_DURATION" -v trim_end="$TRIM_END" 'BEGIN { printf "%.3f", duration - trim_end }')"
  OUTPUT_DURATION="$(awk -v trim_start="$TRIM_START" -v trim_end="$TRIM_END" 'BEGIN { printf "%.3f", trim_end - trim_start }')"
else
  DETECT_LOG=""
  OUTPUT_DURATION="$MANUAL_SECTION_DURATION"
fi

FILTERS=()
if [ "$MANUAL_TRIM" -eq 1 ]; then
  if [ -n "$MANUAL_END_SECONDS" ]; then
    FILTERS+=("atrim=start=${MANUAL_START_SECONDS}:end=${MANUAL_END_SECONDS}" "asetpts=PTS-STARTPTS")
  else
    FILTERS+=("atrim=start=${MANUAL_START_SECONDS}" "asetpts=PTS-STARTPTS")
  fi
fi
if [ "$TRIM_SILENCE" -eq 1 ]; then
  FILTERS+=("atrim=start=${TRIM_START}:end=${TRIM_END}" "asetpts=PTS-STARTPTS")
fi
FILTERS+=("highpass=f=80" "dynaudnorm=f=150:g=15:p=0.95:m=10" "loudnorm=I=-16:LRA=11:TP=-1.5" "alimiter=limit=0.95")
FILTER="$(audio_join_filters "${FILTERS[@]}")"

log_line "Started: $RUN_STARTED"
log_line "Input:  $INPUT"
log_line "Output: $OUTPUT"
log_line "Log:    $LOG"
log_line "Format: $INPUT_FORMAT_NOTE"
if [ -n "$INPUT_PROBE_WARNING" ]; then
  log_line "Probe warning: standard WAV/container probe failed:"
  log_line "$INPUT_PROBE_WARNING"
fi
if [ "$MANUAL_TRIM" -eq 1 ]; then
  if [ -n "$MANUAL_END_TIME" ]; then
    log_line "Manual trim:          $(audio_format_duration "$MANUAL_START_SECONDS") to $(audio_format_duration "$MANUAL_END_SECONDS")"
  else
    log_line "Manual trim:          $(audio_format_duration "$MANUAL_START_SECONDS") to original end"
  fi
  log_line "Manual section length: $(audio_format_duration "$MANUAL_SECTION_DURATION") (${MANUAL_SECTION_DURATION}s)"
fi
if [ "$TRIM_SILENCE" -eq 1 ]; then
  log_line "Silence trim: only leading/trailing silence at $TRIM_THRESHOLD"
  log_line "Original length:       $(audio_format_duration "$INPUT_DURATION") (${INPUT_DURATION}s)"
  if [ "$MANUAL_TRIM" -eq 1 ]; then
    log_line "Silence scan length:   $(audio_format_duration "$MANUAL_SECTION_DURATION") (${MANUAL_SECTION_DURATION}s)"
  fi
  log_line "Silence kept range:    $(audio_format_duration "$TRIM_START") to $(audio_format_duration "$TRIM_END")"
  log_line "Output length:         $(audio_format_duration "$OUTPUT_DURATION") (${OUTPUT_DURATION}s)"
  log_line "Trimmed from start:    $(audio_format_duration "$TRIM_START") (${TRIM_START}s)"
  log_line "Trimmed from end:      $(audio_format_duration "$TRIMMED_END_SECONDS") (${TRIMMED_END_SECONDS}s)"
  if [ "$TRIM_START_WARN" -eq 1 ]; then
    log_line "Warning: skipped start trim because detected silence exceeded ${MAX_AUTO_TRIM}s."
  fi
  if [ "$TRIM_END_WARN" -eq 1 ]; then
    log_line "Warning: skipped end trim because detected silence exceeded ${MAX_AUTO_TRIM}s."
  fi
  if [ "$TRIM_START_WARN" -eq 2 ] || [ "$TRIM_END_WARN" -eq 2 ]; then
    log_line "Warning: skipped automatic trim because the recording looked too quiet or ambiguous."
    log_line "Try --trim-threshold -70dB, --no-trim-silence, or --start/--end."
  fi
  log_line "Silence detect log: $DETECT_LOG"
else
  if [ "$MANUAL_TRIM" -eq 1 ]; then
    log_line "Silence trim: disabled"
  else
    log_line "Trim:   disabled"
  fi
fi
log_line
log_line "Working: ffmpeg progress appears below."
log_line

if [ "${#FFMPEG_INPUT_ARGS[@]}" -gt 0 ]; then
  ffmpeg -y -hide_banner "${FFMPEG_INPUT_ARGS[@]}" -i "$INPUT" \
    -af "$FILTER" \
    -ar 44100 \
    -ac 1 \
    -codec:a libmp3lame \
    -b:a 96k \
    "$OUTPUT" 2>&1 | tee -a "$LOG"
else
  ffmpeg -y -hide_banner -i "$INPUT" \
    -af "$FILTER" \
    -ar 44100 \
    -ac 1 \
    -codec:a libmp3lame \
    -b:a 96k \
    "$OUTPUT" 2>&1 | tee -a "$LOG"
fi

log_line
log_line "Finished: $(date '+%Y-%m-%d %H:%M:%S')"
log_line "Log:"
log_line "$LOG"
audio_next_steps "$OUTPUT" "$ROOT_DIR" | tee -a "$LOG"
