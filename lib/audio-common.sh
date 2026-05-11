#!/bin/bash

audio_die() {
  echo "Error: $*" >&2
  exit 1
}

audio_require_command() {
  command -v "$1" >/dev/null 2>&1 || audio_die "$1 is required but was not found in PATH"
}

audio_script_dir() {
  local source="${BASH_SOURCE[0]}"
  local dir
  while [ -h "$source" ]; do
    dir="$(cd -P "$(dirname "$source")" >/dev/null 2>&1 && pwd)"
    source="$(readlink "$source")"
    [[ "$source" != /* ]] && source="$dir/$source"
  done
  cd -P "$(dirname "$source")/.." >/dev/null 2>&1 && pwd
}

audio_abs_path() {
  local path="$1"
  local dir
  local base

  if [ -d "$path" ]; then
    cd "$path" >/dev/null 2>&1 && pwd -P
    return
  fi

  dir="$(dirname "$path")"
  base="$(basename "$path")"
  cd "$dir" >/dev/null 2>&1 || return 1
  printf '%s/%s\n' "$(pwd -P)" "$base"
}

audio_is_audio_file() {
  local file="$1"
  local lower
  lower="$(printf '%s\n' "$file" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    *.wav|*.mp3|*.m4a|*.aac|*.flac|*.aiff|*.aif) return 0 ;;
    *) return 1 ;;
  esac
}

audio_find_latest() {
  local folder="$1"
  local file
  local mtime
  local latest=""
  local latest_mtime=0

  [ -d "$folder" ] || return 1

  while IFS= read -r -d '' file; do
    mtime="$(stat -f '%m' "$file" 2>/dev/null || stat -c '%Y' "$file")"
    if [ "$mtime" -gt "$latest_mtime" ]; then
      latest_mtime="$mtime"
      latest="$file"
    fi
  done < <(find "$folder" -maxdepth 1 -type f \( \
    -iname "*.wav" -o \
    -iname "*.mp3" -o \
    -iname "*.m4a" -o \
    -iname "*.aac" -o \
    -iname "*.flac" -o \
    -iname "*.aiff" -o \
    -iname "*.aif" \
  \) -print0)

  printf '%s\n' "$latest"
}

audio_name_without_ext() {
  local file="$1"
  local base
  base="$(basename "$file")"
  printf '%s\n' "${base%.*}"
}

audio_default_outdir_for() {
  local input="$1"
  printf '%s/Processed Sermons\n' "$(dirname "$input")"
}

audio_default_output() {
  local input="$1"
  local suffix="$2"
  local outdir="${3:-}"

  [ -n "$outdir" ] || outdir="$(audio_default_outdir_for "$input")"
  printf '%s/%s%s.mp3\n' "$outdir" "$(audio_name_without_ext "$input")" "$suffix"
}

audio_join_filters() {
  local IFS=,
  printf '%s\n' "$*"
}

audio_notify() {
  local title="$1"
  local message="$2"

  command -v osascript >/dev/null 2>&1 || return 0
  osascript -e "display notification \"${message//\"/\\\"}\" with title \"${title//\"/\\\"}\"" >/dev/null 2>&1 || true
}

audio_quote() {
  printf '%q' "$1"
}

audio_format_duration() {
  local seconds="$1"

  awk -v total="$seconds" '
    BEGIN {
      if (total < 0) {
        total = 0
      }
      rounded = int(total + 0.5)
      hours = int(rounded / 3600)
      minutes = int((rounded % 3600) / 60)
      secs = rounded % 60

      if (hours > 0) {
        printf "%d:%02d:%02d", hours, minutes, secs
      } else {
        printf "%d:%02d", minutes, secs
      }
    }
  '
}

audio_next_steps() {
  local output="$1"
  local script_dir="$2"
  local output_dir
  output_dir="$(dirname "$output")"

  echo
  echo "Saved file:"
  echo "$output"
  echo
  echo "To locate it:"
  echo "open $(audio_quote "$output_dir")"
  echo
  echo "To crop it afterward:"
  echo "$(audio_quote "$script_dir/crop-audio.sh") $(audio_quote "$output") START_TIME END_TIME"
  echo "Example:"
  echo "$(audio_quote "$script_dir/crop-audio.sh") $(audio_quote "$output") 1:12 42:30"
}

audio_parse_time() {
  local value="$1"
  local first second third

  if [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$value"
    return
  fi

  if [[ "$value" =~ ^[0-9]+:[0-5]?[0-9]$ ]]; then
    IFS=: read -r first second <<< "$value"
    printf '%s\n' $((10#$first * 60 + 10#$second))
    return
  fi

  if [[ "$value" =~ ^[0-9]+:[0-5]?[0-9]:[0-5]?[0-9]$ ]]; then
    IFS=: read -r first second third <<< "$value"
    printf '%s\n' $((10#$first * 3600 + 10#$second * 60 + 10#$third))
    return
  fi

  audio_die "Invalid time '$value'. Use seconds, min:sec, or hour:min:sec."
}

audio_wait_until_stable() {
  local file="$1"
  local previous_size="-1"
  local current_size
  local stable_count=0

  [ -f "$file" ] || audio_die "File does not exist: $file"

  while [ "$stable_count" -lt 3 ]; do
    current_size="$(stat -f '%z' "$file" 2>/dev/null || stat -c '%s' "$file")"
    if [ "$current_size" = "$previous_size" ]; then
      stable_count=$((stable_count + 1))
    else
      stable_count=0
      previous_size="$current_size"
    fi
    sleep 2
  done
}
