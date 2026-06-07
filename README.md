# Process Sermon Audio

Small ffmpeg tools for cleaning up sermon recordings.

## Main Workflow

```bash
./process-audio.sh ~/Downloads/sermon.wav
```

On macOS, a non-technical user can double-click `process-audio.command`, choose the sermon audio file, choose where to save the processed MP3, and wait for the output folder to open.

The main processor now uses dynamic audio normalization (`dynaudnorm`) because that has worked best for these recordings. It also trims only leading/trailing silence, preserves pauses in the middle, applies a high-pass filter, normalizes final loudness, limits peaks, and exports a mono MP3.

Default output goes to:

```text
~/Documents/Processed
```

While it runs, Terminal shows ffmpeg progress. Each run also writes a log beside the MP3.

Common options:

```bash
./process-audio.sh ~/Downloads/sermon.wav --no-trim-silence
./process-audio.sh ~/Downloads/sermon.wav --trim-threshold -65dB
./process-audio.sh ~/Downloads/sermon.wav --max-auto-trim 120
./process-audio.sh ~/Downloads/sermon.wav --outdir ~/Desktop/Processed
./process-audio.sh ~/Downloads/sermon.wav --log ~/Desktop/sermon-process.log
```

When processing finishes, the script prints the saved file path and an `open ...` command for the output folder.

## Trim Manually

Trim only the beginning and keep the original end:

```bash
./trim-audio.sh sermon.wav 1:12
```

Keep only a specific section:

```bash
./trim-audio.sh sermon.wav 1:12 42:30
```

For non-technical use, run it without arguments and answer the prompts:

```bash
./trim-audio.sh
```

On macOS, a non-technical user can also double-click `trim-audio.command` and answer the prompts in the Terminal window.

Times can be seconds, `min:sec`, or `hour:min:sec`.

## Silence Sensitivity

The default trim threshold is `-60dB`, which is conservative for quiet sermon recordings. If quiet speech is ever trimmed, use a lower number like `-65dB` or disable auto-trim with `--no-trim-silence`. If it leaves too much dead air at the edges, use a higher number like `-50dB`.

## Extra Scripts

Less common scripts are in `extras/`:

```text
extras/process-latest-sermon.sh
extras/rescue-dynaudnorm.sh
extras/rescue-quiet-sections.sh
extras/setup-usb-watch.sh
extras/watch-audio-folder.sh
```

USB auto-processing instructions are in [docs/USB_WATCH_SETUP.md](docs/USB_WATCH_SETUP.md).
