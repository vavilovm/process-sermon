# USB Drive Auto Processing

This project can watch a recorder or USB drive and process a new audio file when the drive appears.

## 1. Install Requirements

Install `ffmpeg` and `fswatch`:

```bash
brew install ffmpeg fswatch
```

## 2. Find The Drive Path

Connect the recorder or USB drive and look in `/Volumes`:

```bash
ls /Volumes
```

If the drive is named `ZOOM H1N`, its path is:

```text
/Volumes/ZOOM H1N
```

If recordings are inside a folder on the drive, include that folder too:

```text
/Volumes/ZOOM H1N/FOLDER01
```

## 3. Test The Watcher Manually

Run:

```bash
./extras/watch-audio-folder.sh "/Volumes/ZOOM H1N"
```

Or, if recordings are in a subfolder:

```bash
./extras/watch-audio-folder.sh "/Volumes/ZOOM H1N/FOLDER01"
```

Leave that Terminal window open. When a new audio file appears, the watcher waits until the file size is stable and then runs `process-audio.sh`.

You will see messages in Terminal when a file is detected, when processing starts, and when it finishes.

By default, output goes to:

```text
~/Documents/sermons
```

To put processed files somewhere else:

```bash
./extras/watch-audio-folder.sh "/Volumes/ZOOM H1N/FOLDER01" --outdir "$HOME/Desktop/Processed"
```

## 4. Start Automatically At Login

Use the setup script:

```bash
./extras/setup-usb-watch.sh "ZOOM H1N"
```

With a recordings subfolder:

```bash
./extras/setup-usb-watch.sh "ZOOM H1N" "FOLDER01"
```

With output on your computer instead of the USB drive:

```bash
./extras/setup-usb-watch.sh "ZOOM H1N" "FOLDER01" --outdir "$HOME/Desktop/Processed"
```

The setup script creates:

```text
~/Library/LaunchAgents/com.local.process-sermon-usb.plist
```

The watcher starts at login. If the drive is not connected yet, it waits until the expected folder appears under `/Volumes`.

LaunchAgent output logs are written here:

```text
~/Library/Logs/process-sermon/watch.log
~/Library/Logs/process-sermon/watch.err.log
```

Each processed audio run also creates a log beside the saved MP3, for example:

```text
~/Documents/sermons/recording-processed.log
```

## 5. Stop Or Remove The Watcher

Unload it:

```bash
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.local.process-sermon-usb.plist"
```

Remove it:

```bash
rm "$HOME/Library/LaunchAgents/com.local.process-sermon-usb.plist"
```

## Notes

`fswatch` can watch a USB drive folder once it exists. For a drive that may not be connected yet, the LaunchAgent starts `extras/watch-audio-folder.sh`, and that script waits for `/Volumes/DRIVE NAME` to appear.

If the drive name changes, rerun `extras/setup-usb-watch.sh` with the new drive name.
