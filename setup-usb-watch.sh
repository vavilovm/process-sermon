#!/bin/bash
# Create a macOS LaunchAgent that starts watch-audio-folder.sh at login.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  ./setup-usb-watch.sh "DRIVE NAME" [SUBFOLDER] [--outdir DIR]

Examples:
  ./setup-usb-watch.sh "ZOOM H1N"
  ./setup-usb-watch.sh "ZOOM H1N" "FOLDER01" --outdir ~/Desktop/Processed

This creates ~/Library/LaunchAgents/com.local.process-sermon-usb.plist.
It does not install fswatch for you. Install it first with:
  brew install fswatch
USAGE
}

[ "$#" -gt 0 ] || { usage; exit 1; }
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

DRIVE_NAME="$1"
shift
SUBFOLDER=""
OUTDIR=""

if [ "$#" -gt 0 ] && [[ "${1:-}" != --* ]]; then
  SUBFOLDER="$1"
  shift
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --outdir)
      OUTDIR="${2:-}"
      [ -n "$OUTDIR" ] || { echo "Error: --outdir requires a folder" >&2; exit 1; }
      shift 2
      ;;
    *)
      echo "Error: unknown option: $1" >&2
      exit 1
      ;;
  esac
done

WATCH_FOLDER="/Volumes/$DRIVE_NAME"
if [ -n "$SUBFOLDER" ]; then
  WATCH_FOLDER="$WATCH_FOLDER/$SUBFOLDER"
fi

LABEL="com.local.process-sermon-usb"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/process-sermon"
mkdir -p "$(dirname "$PLIST")" "$LOG_DIR"

PROGRAM_ARGS="
    <string>$ROOT_DIR/watch-audio-folder.sh</string>
    <string>$WATCH_FOLDER</string>"

if [ -n "$OUTDIR" ]; then
  PROGRAM_ARGS="$PROGRAM_ARGS
    <string>--outdir</string>
    <string>$OUTDIR</string>"
fi

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
$PROGRAM_ARGS
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/watch.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/watch.err.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "Installed LaunchAgent:"
echo "$PLIST"
echo
echo "Watching:"
echo "$WATCH_FOLDER"
echo
echo "Logs:"
echo "$LOG_DIR/watch.log"
echo "$LOG_DIR/watch.err.log"
