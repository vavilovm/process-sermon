# Process Sermon Audio

Small ffmpeg scripts for sermon recording cleanup, trimming, and rescue work.

## Process One File

```bash
./process-sermon.sh ~/Downloads/sermon.wav
```

This trims only leading/trailing silence, applies a high-pass filter, normalizes loudness, limits peaks, and exports a mono MP3. Pauses in the middle of the sermon are preserved.

While it runs, Terminal shows ffmpeg progress. Each run also writes a log beside the MP3, for example `sermon-processed.log`.

Common options:

```bash
./process-sermon.sh ~/Downloads/sermon.wav --outdir ~/Desktop/Processed
./process-sermon.sh ~/Downloads/sermon.wav --no-trim-silence
./process-sermon.sh ~/Downloads/sermon.wav --trim-threshold -65dB
./process-sermon.sh ~/Downloads/sermon.wav --max-auto-trim 120
./process-sermon.sh ~/Downloads/sermon.wav --log ~/Desktop/sermon-process.log
```

When processing finishes, the script prints the saved file path, an `open ...` command for the output folder, and the crop command to use if the beginning/end still need manual trimming.

Silence sensitivity:

The default trim threshold is `-60dB`, which is conservative for quiet sermon recordings. If quiet speech is ever trimmed, use a lower number like `-65dB` or disable auto-trim with `--no-trim-silence`. If it leaves too much dead air at the edges, use a higher number like `-50dB`.

Volume:

The normal processing script already raises the final sermon to a consistent loudness target with `loudnorm`. If the recording has sections where the speaker gets much quieter or louder, use `rescue-dynaudnorm.sh` after checking the normal processed output.

## Process The Latest File In A Folder

```bash
./process-latest-sermon.sh
```

Defaults to `~/Downloads`.

```bash
./process-latest-sermon.sh "/Volumes/ZOOM H1N/FOLDER01"
./process-latest-sermon.sh ~/Downloads --outdir ~/Desktop/Processed
```

## Crop Beginning And End

Keep only the part from start time to end time:

```bash
./crop-audio.sh sermon.wav 1:12 42:30
```

For non-technical use, run it without arguments and answer the prompts:

```bash
./crop-audio.sh
```

On macOS, a non-technical user can also double-click `crop-audio.command` and answer the prompts in the Terminal window.

Times can be seconds, `min:sec`, or `hour:min:sec`.

## Rescue Uneven Volume

Use this when the whole recording has uneven loudness:

```bash
./rescue-dynaudnorm.sh sermon.wav
```

## Rescue Known Quiet Sections

Use this when only known time ranges are too quiet:

```bash
./rescue-quiet-sections.sh sermon.wav --section 2:10-3:05 --section 21:00-22:15
```

Change the boost amount:

```bash
./rescue-quiet-sections.sh sermon.wav --section 2:10-3:05 --boost 12dB
```

If a section is truly silent because no audio was recorded, boosting cannot recover speech that is not there. This script helps when the speech exists but is much quieter than the rest.

## USB Auto Processing

See [docs/USB_WATCH_SETUP.md](docs/USB_WATCH_SETUP.md).
