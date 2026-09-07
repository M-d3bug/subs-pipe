# subs-pipe

Media → `.srt` subtitles, Groq-first with Colab fallback. Short name on purpose: the provider/model can change, the pipe stays.

Single Windows entry point (`subs-pipe.cmd`) + optional Colab notebook. Filenames are anonymized during transcription, then restored.

[![Open In Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/M-d3bug/subs-pipe/blob/main/transcribe_colab.ipynb)

> Renamed from `colab-whisper`. Old `prepare_videos.cmd` was removed from `main` (still in git history).

---

## Quickstart (Groq automatic, recommended)

1. Put `subs-pipe.cmd` in an empty folder. Double-click it.
2. Press `F` once to install/check `ffmpeg` (needed for converts + >25 MB files).
3. Press `1`, drop files/folder or paste a path. Converts to `upload\video_1.mp3`, `video_2.mp3`, … names saved in `upload\names.log`.
4. Press `2`, optionally add flags (e.g. `--lang en --force`). Enter your `GROQ_API_KEY` once when asked — get one free at https://console.groq.com/keys, offered to save to `.env` beside the script.
5. Done: real-named `.srt` files land in `subtitles\`.

No Groq? Use Colab fallback:

1. Do step 3 above.
2. Open the badge notebook, upload `upload\*.mp3` to `audio_files/`, Run all, download `transcripts.zip`.
3. Unzip into `subtitles\`, press `3` in the menu to restore real names.

---

## Direct mode (no menu, drag-drop + CLI)

```bat
subs-pipe.cmd "C:\Audio\talk.mp3" --lang en
subs-pipe.cmd C:\Audio --recursive
subs-pipe.cmd "C:\Audio" --outdir "C:\Subs" --force --dry-run
```

| Flag | Default | What |
|------|---------|------|
| `--lang CODE` | auto | e.g. `en`, `es`, `de` |
| `--prompt TEXT` | — | style/spelling hint, same language as audio |
| `--model NAME` | `whisper-large-v3-turbo` | also `whisper-large-v3` |
| `--outdir DIR` | beside input | write `.srt` elsewhere |
| `--max-line N` | `42` | max chars per line |
| `--max-sec SEC` | `5` | max seconds per cue |
| `--force` | off | re-transcribe even if `.srt` newer |
| `--recursive` | off | include subfolders |
| `--keep-json` | off | keep raw `.verbose.json` |
| `--dry-run` | off | list only, no upload |
| `--help` | — | full help |

API key order: `--apikey` → `%GROQ_API_KEY%` → `.env` (`GROQ_API_KEY=...`) → prompt.

---

## What you need

* Windows 10/11 + `ffmpeg` (press `F`, or `winget install -e --id Gyan.FFmpeg`)
* Groq key for automatic mode, or Google account for Colab fallback
* Inputs: `.mp4 .mkv .avi .mov .webm .wmv .mp3 .wav .m4a .flac .ogg .aac .mpeg .mpga`

Large files (>25 MB Groq free-tier limit): auto-compress to 16 kHz mono 64k MP3, else split into ~10-min chunks and stitch timestamps back.

---

## Folders

```
<folder beside subs-pipe.cmd>\
  upload\       in:  video_1.mp3 … + names.log (anonymized)
  subtitles\    out: <realname>.srt
  .env          GROQ_API_KEY=... (git-ignored, never commit)
  tools\        portable ffmpeg fallback (git-ignored)
```

Privacy: only `video_N.mp3` is uploaded. `names.log` stays local and maps `N → original name` for restore.

---

## Files in this repo

| File | What |
|------|------|
| `subs-pipe.cmd` | menu + Groq transcribe + Colab restore + ffmpeg installer (single file) |
| `transcribe_colab.ipynb` | optional Colab fallback (Groq is default) |
| `README.md` | this file |

Removed from `main` (in history): `prepare_videos.cmd` — superseded by option `1` in `subs-pipe.cmd`.

---

## Troubleshooting

* `ffmpeg not found` → press `F`, reopen script (PATH refresh).
* `401 / invalid_api_key` → new key at console.groq.com/keys, check spaces, delete bad `.env` line.
* `No prepared files` → press `1` first.
* `names.log missing/empty` → you cleared `upload\`, re-run `1`.
* `SRT skipped, already restored?` → normal if option `2/3` ran twice; use `--force` in direct mode.
* Colab `No MP3 found` → upload into `audio_files/`, re-run cell.

---

## Credits

* Transcription: Groq `whisper-large-v3-turbo` / OpenAI Whisper (Colab)
* Audio: FFmpeg
* License: MIT — see `LICENSE`
