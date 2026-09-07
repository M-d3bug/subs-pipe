# subs-pipe

Media -> `.srt` subtitles. Groq-first, Colab fallback.

One Windows file does the pipe. Names are anonymized for upload, then restored.

**[Download subs-pipe.cmd](https://github.com/M-d3bug/subs-pipe/raw/main/subs-pipe.cmd)** - [![Open In Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/M-d3bug/subs-pipe/blob/main/transcribe_colab.ipynb)

---

## Quickstart - Groq automatic

1. Download **[subs-pipe.cmd](https://github.com/M-d3bug/subs-pipe/raw/main/subs-pipe.cmd)**, put it in an empty folder, double-click it.
2. Press `F` - installs/checks `ffmpeg`.
3. Press `1` - drop files, a folder, or paste a path. Makes `upload\video_1.mp3`, ... + `upload\names.log`.
4. Press `2` - transcribes to `subtitles\` with real names. First run asks for `GROQ_API_KEY` ([free key](https://console.groq.com/keys)), offers to save to `.env`.
5. Done. `.srt` files are in `subtitles\`.

Tip: `2` accepts flags, e.g. `--lang en --force`.

### Colab fallback - only if you skip Groq

1. Do Quickstart step 3 above.
2. Open the Colab badge, upload `upload\*.mp3` to `audio_files/`, Run all, download `transcripts.zip`.
3. Unzip into `subtitles\`, press `3` to restore real names.

---

## Direct mode - no menu

Drag-drop onto the `.cmd`, or:

```bat
subs-pipe.cmd "C:\Audio\talk.mp3" --lang en
subs-pipe.cmd C:\Audio --recursive
subs-pipe.cmd C:\Audio --outdir C:\Subs --force --dry-run
```

| Flag | Default | Notes |
|------|---------|-------|
| `--lang CODE` | auto | `en`, `es`, `de` ... |
| `--prompt TEXT` | — | spelling/style hint, same language as audio |
| `--model NAME` | `whisper-large-v3-turbo` | also `whisper-large-v3` |
| `--outdir DIR` | beside input | where `.srt` goes |
| `--max-line N` | `42` | chars per line |
| `--max-sec SEC` | `5` | seconds per cue |
| `--force` | off | redo even if `.srt` is newer |
| `--recursive` | off | include subfolders |
| `--keep-json` | off | keep `.verbose.json` |
| `--dry-run` | off | list only |
| `--help` | — | full help |

Key order: `--apikey` -> `%GROQ_API_KEY%` -> `.env` -> prompt.

---

## Requirements

* Windows 10/11.
* `ffmpeg` - press `F` in the script, or `winget install -e --id Gyan.FFmpeg`.
* Groq key **or** Google account for Colab.
* Inputs: `.mp4 .mkv .avi .mov .webm .wmv .mp3 .wav .m4a .flac .ogg .aac .mpeg .mpga`.

> Over ~25 MB? Auto-compresses to 16 kHz mono 64k MP3, else splits into ~10-min chunks and stitches timestamps.

---

## Folders

```
<folder beside subs-pipe.cmd>\
  upload\      in:  video_1.mp3 ... + names.log
  subtitles\   out: <realname>.srt
  .env         GROQ_API_KEY=... (never commit)
  tools\       portable ffmpeg fallback
```

Only `video_N.mp3` is uploaded. `names.log` stays local for restore.

---

## Files

| File | Purpose |
|------|---------|
| [`subs-pipe.cmd`](https://github.com/M-d3bug/subs-pipe/raw/main/subs-pipe.cmd) | menu + Groq + Colab restore + ffmpeg setup |
| `transcribe_colab.ipynb` | optional Colab fallback |
| `README.md` | this file |

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `ffmpeg not found` | Press `F`, reopen script |
| `401 / invalid key` | New key at [console.groq.com/keys](https://console.groq.com/keys), fix `.env` |
| `No prepared files` | Press `1` first |
| `names.log missing` | Re-run `1`, don't delete `upload\` mid-run |
| `SRT skipped?` | Already restored - use `--force` to redo |
| Window closed during restore | Re-download `subs-pipe.cmd` (fixed) and press `3` to finish renaming |
| Colab `No MP3 found` | Upload into `audio_files/`, re-run cell |

---

## Credits

* Groq `whisper-large-v3-turbo` / OpenAI `Whisper` /Google `Colab Notebook` / FFmpeg - MIT, see `LICENSE`

