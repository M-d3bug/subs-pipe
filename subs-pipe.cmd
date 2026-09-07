<# :
@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem subs-pipe: video/audio ingest + Groq Whisper large-v3-turbo audio to SRT.
rem No arguments = interactive pipeline menu. Audio paths / transcribe flags
rem (drag-drop, CLI) = direct transcribe mode.
rem Internal: menu item 2 sets GROQ_FROM_MENU=1 and re-invokes this file.
if defined GROQ_FROM_MENU goto :run_ps
if not "%~1"=="" goto :run_ps
rem Central paths: upload\ and subtitles\ live beside this script.
set "script_dir=%~dp0"
set "upload_dir=%script_dir%upload"
set "subtitles_dir=%script_dir%subtitles"
set "name_log=%upload_dir%\names.log"
setlocal EnableDelayedExpansion
call :ensure_folders
goto :menu

REM Ensure upload and subtitles directories exist
:ensure_folders
if not exist "%upload_dir%" mkdir "%upload_dir%"
if not exist "%subtitles_dir%" mkdir "%subtitles_dir%"
exit /b

REM Main menu
:menu
cls
echo.
echo ==============================================================
echo   Whisper Audio/Video Transcriber
echo ==============================================================
echo   1. Ingest ^& Anonymize (Drag ^& drop media -^> upload\)
echo   2. Transcribe ^& Restore Names (Groq Automatic -^> subtitles\)
echo   3. Restore Colab SRT Names (Colab Download -^> subtitles\)
echo --------------------------------------------------------------
echo   O. Open Folders (upload / subtitles)
echo   F. Install / Check ffmpeg
echo   H. Help ^& Colab Guide
echo   5. Exit
echo ==============================================================
echo.
set "choice="
set /p choice=Choice (1-3, O, F, H, 5): 
if defined choice set "choice=!choice: =!"
if defined choice set "choice=!choice:"=!"

if "!choice!"=="1" goto :do_ingest
if "!choice!"=="2" goto :do_transcribe
if "!choice!"=="3" goto :do_restore_colab
if /i "!choice!"=="o" goto :do_open
if "!choice!"=="5" exit /b
if /i "!choice!"=="f" goto :do_ffmpeg
if /i "!choice!"=="h" goto :do_help

goto :menu

:do_ingest
call :ingest_media
pause
goto :menu

:do_transcribe
call :transcribe_groq
pause
goto :menu

:do_restore_colab
call :restore_colab_srts
pause
goto :menu

:do_open
call :open_folders
goto :menu

:do_ffmpeg
call :install_ffmpeg
pause
goto :menu

:do_help
call :show_help
pause
goto :menu

:show_help
cls
echo.
echo ==============================================================
echo   Help - What Goes Where
echo ==============================================================
echo   Turns video/audio into .srt subtitles. File names are hidden
echo   during transcription, then restored afterwards.
echo --------------------------------------------------------------
echo   GROQ WAY (automatic)
echo   1. Press 1: drop files in -^> converted to upload\ as
echo      video_1.mp3, video_2.mp3 ... (names saved in names.log).
echo   2. Press 2: Groq transcribes upload\ -^> finished .srt files
echo      land in subtitles\ with their real names.
echo --------------------------------------------------------------
echo   COLAB WAY (manual)
echo   1. Press 1 to prepare upload\ as above.
echo   2. Upload those MP3s to this notebook:
echo      ^<https://colab.research.google.com/github/M-d3bug/subs-pipe/blob/main/transcribe_colab.ipynb^>
echo   3. Download the .srt files into subtitles\.
echo   4. Press 3 to restore their real names.
echo --------------------------------------------------------------
echo   Folders: upload\ (in)   subtitles\ (out)   .env (beside script)
echo ==============================================================
exit /b

REM Open staging and output folders in Windows Explorer
:open_folders
call :ensure_folders
start "" explorer.exe "!upload_dir!"
start "" explorer.exe "!subtitles_dir!"
exit /b

REM Step 1: Ingest and anonymize media
:ingest_media
cls
echo.
echo ==============================================================
echo   Step 1 of 2 - Ingest ^& Anonymize Media
echo ==============================================================
echo.
call :ensure_folders

where ffmpeg >nul 2>nul
if not errorlevel 1 goto :ingest_ffmpeg_ok
echo Error: ffmpeg not found in PATH. Press F in the menu to install it.
exit /b
:ingest_ffmpeg_ok

REM Check if upload folder already has files
REM NOTE: plain FOR over a wildcard counts a non-match as 1, so count via dir+find.
set /a existing_count=0
for /f %%A in ('dir /b "!upload_dir!\video_*.mp3" 2^>nul ^| find /c /v ""') do set /a existing_count=%%A
if !existing_count! leq 0 goto :ingest_no_prev
echo NOTE: !existing_count! old file^(s^) in upload\.
set "clean_choice="
set /p "clean_choice=Clear them before ingesting new ones? [Y/n]: "
if /i "!clean_choice!"=="n" goto :ingest_no_prev
del /q /f "!upload_dir!\video_*.mp3" 2>nul
del /q /f "!upload_dir!\names.log" 2>nul
echo Cleared upload\ folder.
echo.
:ingest_no_prev

if not exist "!name_log!" type nul > "!name_log!"

echo Drop files or a folder here, paste a path,
echo or press Enter to scan this folder:
set "input_path="
set /p "input_path=> "
if not defined input_path set "input_path=%script_dir%"

REM Strip enclosing quotes for single-target checks
set "input_clean=!input_path:"=!"
REM Strip one trailing backslash so "dir\" + "\*" does not become "\\*".
REM Restore it for drive roots like C:\ .
if "!input_clean:~-1!"=="\" set "input_clean=!input_clean:~0,-1!"
if "!input_clean:~-1!"==":" set "input_clean=!input_clean!\"

set /a counter=1
REM Find highest existing index if keeping files
for /f "tokens=2 delims=_." %%C in ('dir /b "!upload_dir!\video_*.mp3" 2^>nul') do (
    if %%C geq !counter! set /a counter=%%C+1
)

set /a converted=0
set /a skipped=0

REM Route without parenthesised ELSE blocks: paths containing ) or &
REM would otherwise break the block parser and kill the window.
if exist "!input_clean!\*" goto :ingest_is_dir
if exist "!input_clean!" goto :ingest_is_file
goto :ingest_is_multi

:ingest_is_dir
echo Scanning: "!input_clean!"...
for %%F in ("!input_clean!\*") do (
    if not exist "%%~F\*" (
        call :process_one_file "%%~F"
    )
)
goto :ingest_scan_done

:ingest_is_file
REM Single file with or without spaces
call :process_one_file "!input_clean!"
goto :ingest_scan_done

:ingest_is_multi
REM May be multiple quoted files dragged together
for %%I in (!input_path!) do (
    if exist "%%~I\*" (
        for %%F in ("%%~I\*") do (
            if not exist "%%~F\*" (
                call :process_one_file "%%~F"
            )
        )
    ) else if exist "%%~I" (
        call :process_one_file "%%~I"
    ) else (
        echo Path not found: "%%~I"
    )
)
:ingest_scan_done

echo.
if !converted! equ 0 goto :ingest_nothing
goto :ingest_had_files
:ingest_nothing
echo Warning: No supported video/audio files were converted.
exit /b
:ingest_had_files

echo ==============================================================
echo SUCCESS: Converted ^& anonymized !converted! file^(s^).
echo -^> Select Option 2 in the menu to transcribe and restore names.
echo ==============================================================
exit /b

:process_one_file
set "src_file=%~1"
set "src_ext=%~x1"
set "src_name=%~n1"

REM Verify supported extension (video or audio)
set "is_supported=0"
for %%E in (.mp4 .mkv .avi .mov .webm .mp3 .wav .m4a .flac .ogg .aac .mpeg .mpga) do (
    if /i "!src_ext!"=="%%E" set "is_supported=1"
)

if not "!is_supported!"=="0" goto :process_supported
set /a skipped+=1
exit /b
:process_supported

set "target_mp3=!upload_dir!\video_!counter!.mp3"
echo [!counter!] Processing: "!src_name!!src_ext!" -^> video_!counter!.mp3
ffmpeg -y -v error -i "!src_file!" -vn -acodec libmp3lame -q:a 2 "!target_mp3!"
if not errorlevel 1 goto :process_ff_ok
echo   Failed to convert: "!src_file!"
set /a skipped+=1
exit /b
:process_ff_ok

REM Record mapping in names.log (line N corresponds to video_N)
echo;!src_name!>>"!name_log!"
set /a counter+=1
set /a converted+=1
exit /b

REM Step 2: Groq Transcribe & Auto-Restore
:transcribe_groq
cls
echo.
echo ==============================================================
echo   Step 2 of 2 - Transcribe ^& Restore Names
echo ==============================================================
echo.
call :ensure_folders

if not exist "!upload_dir!\video_*.mp3" (
    echo Error: No prepared files found in "!upload_dir!".
    echo Please press 1 first to ingest and anonymize your media.
    exit /b
)

set "GROQ_NOPAUSE=1"
set "GROQ_FROM_MENU=1"
setlocal DisableDelayedExpansion
set "GROQ_EXTRA="
set /p "GROQ_EXTRA=Options (Enter = defaults, e.g. --lang en --force): "
REM Strip shell metachars typed at the prompt so the transcribe call below cannot break.
REM Each line is guarded by if defined: substitution on an empty value is unsafe.
if defined GROQ_EXTRA set "GROQ_EXTRA=%GROQ_EXTRA:&= %"
if defined GROQ_EXTRA set "GROQ_EXTRA=%GROQ_EXTRA:|= %"
if defined GROQ_EXTRA set "GROQ_EXTRA=%GROQ_EXTRA:<= %"
if defined GROQ_EXTRA set "GROQ_EXTRA=%GROQ_EXTRA:>= %"
if defined GROQ_EXTRA set "GROQ_EXTRA=%GROQ_EXTRA:(= %"
if defined GROQ_EXTRA set "GROQ_EXTRA=%GROQ_EXTRA:)= %"
cmd /v:off /d /c ""%~f0" --outdir "%subtitles_dir%" "%upload_dir%" %GROQ_EXTRA%"
REM Preserve ERRORLEVEL across endlocal: the full line is expanded before
REM execution, so %ERRORLEVEL% still holds cmd's exit code when set runs.
endlocal & set "TRANS_EC=%ERRORLEVEL%"

if not "%TRANS_EC%"=="0" (
    echo.
    echo Transcription failed, exit code: %TRANS_EC%
    exit /b
)

echo.
echo Transcription done, restoring original names...
call :restore_srt_names
echo.
echo ==============================================================
echo Done^^! Subtitles are in:
echo   !subtitles_dir!\
echo ==============================================================
exit /b

REM Step 3: Colab Restore
:restore_colab_srts
cls
echo.
echo ==============================================================
echo   Step 3 - Restore Colab SRT Names
echo ==============================================================
echo.
call :ensure_folders

REM If user dropped files in upload\ instead of subtitles\, move them
if exist "!upload_dir!\video_*.srt" (
    echo Moving video_*.srt from upload\ to subtitles\...
    move /y "!upload_dir!\video_*.srt" "!subtitles_dir!\" >nul 2>nul
)

call :restore_srt_names
echo.
echo ==============================================================
echo Done^^! Subtitles are in:
echo   !subtitles_dir!\
echo ==============================================================
exit /b

REM Restores video_N.srt to original_name.srt in subtitles_dir
:restore_srt_names
if not exist "!name_log!" (
    echo Error: names.log is missing from "!upload_dir!". Press 1 first.
    exit /b
)
for %%A in ("!name_log!") do if %%~zA equ 0 (
    echo Error: names.log is empty. Press 1 first.
    exit /b
)
if not exist "!subtitles_dir!" (
    echo Error: Subtitles folder "!subtitles_dir!" not found.
    exit /b
)

set /a restored=0
set /a missing=0
set /a notfound=0
for /f "usebackq tokens=1* delims=:" %%a in (`findstr /n "^^" "!name_log!"`) do (
    set "original_name=%%b"
    set "new_srt_name=video_%%a.srt"

    if defined original_name (
        if exist "!subtitles_dir!\!new_srt_name!" (
            if exist "!subtitles_dir!\!original_name!.srt" (
                echo Overwriting existing: "!original_name!.srt"
                del /f /q "!subtitles_dir!\!original_name!.srt" >nul 2>nul
            )
            ren "!subtitles_dir!\!new_srt_name!" "!original_name!.srt"
            if !errorlevel! equ 0 (
                for /f "delims=" %%o in ("!original_name!") do echo Restored: !new_srt_name! -^> %%o.srt
                set /a restored+=1
            ) else (
                echo Failed to rename: !new_srt_name!
                set /a missing+=1
            )
        ) else (
            echo Skipped: !new_srt_name! - already restored, nothing to do.
            set /a missing+=1
            set /a notfound+=1
        )
    )
)
echo.
echo Summary: !restored! restored, !missing! skipped.
if !restored! equ 0 if !missing! gtr 0 if !notfound! equ !missing! echo Tip: nothing renamed - files were already restored, nothing to do.
exit /b

REM Install ffmpeg and add it to PATH
REM Path 1: winget (Gyan.FFmpeg). Path 2 (fallback): portable zip.
REM The portable download tries a mirror chain (GitHub CDN first,
REM gyan.dev second) with curl resume+retry when available, because a
REM single slow host used to stall the install.
:install_ffmpeg
cls
echo.
echo ==============================================================
echo   Install / Check ffmpeg
echo ==============================================================
echo.
REM Already available? Nothing to do.
where ffmpeg >nul 2>nul
if not errorlevel 1 goto :ffmpeg_already_here
REM Prefer winget when present.
where winget >nul 2>nul
if errorlevel 1 goto :ffmpeg_portable
echo Found winget, installing ffmpeg (Gyan.FFmpeg)...
winget install -e --id Gyan.FFmpeg --accept-source-agreements --accept-package-agreements
if errorlevel 1 goto :ffmpeg_portable
call :refresh_path
where ffmpeg >nul 2>nul
if not errorlevel 1 (
    echo SUCCESS: ffmpeg installed (winget):
    ffmpeg -version 2>nul | findstr /i "ffmpeg version"
    exit /b
)
echo Winget done, but ffmpeg is still missing. Trying portable download...
goto :ffmpeg_portable

:ffmpeg_already_here
echo ffmpeg is already installed:
for /f "delims=" %%P in ('where ffmpeg') do echo   %%P
ffmpeg -version 2>nul | findstr /i "ffmpeg version"
exit /b

:ffmpeg_portable
REM Portable fallback: download a release zip next to the script.
REM NOTE: downloader lines below deliberately contain no parentheses,
REM so they stay safe if this section is ever wrapped in a
REM parenthesised block (cmd parses parens even inside quotes).
set "tools_dir=%script_dir%tools"
set "ffmpeg_root=%script_dir%tools\ffmpeg"
set "ffmpeg_zip=%script_dir%tools\ffmpeg-dist.zip"
if not exist "%tools_dir%" mkdir "%tools_dir%"
if not exist "%ffmpeg_root%" mkdir "%ffmpeg_root%"
echo Mirror 1 of 2: BtbN release via GitHub CDN...
call :download_one "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
if not errorlevel 1 goto :ffmpeg_extract
echo Mirror 1 failed, trying mirror 2...
del "%ffmpeg_zip%" >nul 2>nul
echo Mirror 2 of 2: gyan.dev release essentials (~80 MB)...
call :download_one "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
if not errorlevel 1 goto :ffmpeg_extract
echo Error: download failed on all mirrors. Check your connection and try again.
exit /b
:ffmpeg_extract
echo Extracting a fresh copy...
rd /s /q "%ffmpeg_root%" >nul 2>nul
mkdir "%ffmpeg_root%" >nul 2>nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Path '%ffmpeg_zip%' -DestinationPath '%ffmpeg_root%' -Force"
if errorlevel 1 (
    echo Error: extraction failed.
    exit /b
)
set "ffmpeg_bin="
if exist "%ffmpeg_root%\bin\ffmpeg.exe" set "ffmpeg_bin=%ffmpeg_root%\bin"
if not defined ffmpeg_bin call :find_ffmpeg_exe
if not defined ffmpeg_bin (
    echo Error: ffmpeg.exe not found after extraction.
    exit /b
)
set "addPath=!ffmpeg_bin!"
call :add_dir_to_user_path
del "%ffmpeg_zip%" >nul 2>nul
where ffmpeg >nul 2>nul
if not errorlevel 1 (
    echo SUCCESS: ffmpeg installed:
    ffmpeg -version 2>nul | findstr /i "ffmpeg version"
) else (
    echo Error: ffmpeg still missing. Restart this script and try again.
)
exit /b

REM Downloads %~1 to %ffmpeg_zip%. Prefers curl with resume and
REM retries; falls back to PowerShell. Returns 0 on success.
:download_one
where curl >nul 2>nul
if errorlevel 1 goto :download_one_ps
curl.exe -fSL --retry 3 --retry-delay 2 -C - -o "%ffmpeg_zip%" "%~1"
if not errorlevel 1 exit /b 0
REM Resume can fail if the build changed server-side; retry once fresh.
del "%ffmpeg_zip%" >nul 2>nul
curl.exe -fSL --retry 3 --retry-delay 2 -o "%ffmpeg_zip%" "%~1"
exit /b
:download_one_ps
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri '%~1' -OutFile '%ffmpeg_zip%' -UseBasicParsing"
exit /b

REM Recursively locates ffmpeg.exe under %ffmpeg_root% regardless of which
REM mirror layout was extracted (Gyan vs BtbN folder names differ).
REM NOTE: the FOR /R root must use %ffmpeg_root% (percent), NOT
REM !ffmpeg_root!: a delayed-expansion root is misread as relative and gets
REM the current directory prepended. FOR /R also generates names without
REM checking existence, so every hit is verified with IF EXIST.
:find_ffmpeg_exe
for /r "%ffmpeg_root%" %%E in (ffmpeg.exe) do (
    if exist "%%E" (
        if not defined ffmpeg_bin set "ffmpeg_bin=%%~dpE"
    )
)
if defined ffmpeg_bin if "!ffmpeg_bin:~-1!"=="\" set "ffmpeg_bin=!ffmpeg_bin:~0,-1!"
exit /b

REM Adds %addPath% to the user PATH (persisted via setx) and to the
REM current session PATH so ffmpeg works immediately. Idempotent:
REM already-present entries are not duplicated.
:add_dir_to_user_path
if "%addPath%"=="" (
    echo Error: internal error, no directory to add to PATH.
    exit /b
)
REM Session PATH first. !PATH! with delayed expansion is safe here:
REM special chars from the value are not re-parsed.
echo;!PATH!;| findstr /i /c:";!addPath!;" >nul
if errorlevel 1 set "PATH=!addPath!;!PATH!"
REM Read persisted user PATH.
set "userPath="
for /f "tokens=2*" %%A in ('reg query "HKCU\Environment" /v Path 2^>nul ^| findstr /i "REG_"') do set "userPath=%%B"
if not defined userPath goto :persist_new_user_path
echo;!userPath!;| findstr /i /c:";!addPath!;" >nul
if not errorlevel 1 (
    echo Already on PATH: !addPath!
    exit /b
)
set "newUserPath=!userPath!;!addPath!"
goto :persist_write_path
:persist_new_user_path
set "newUserPath=!addPath!"
:persist_write_path
setx Path "!newUserPath!" >nul
if errorlevel 1 (
    echo Warning: could not persist PATH with setx. ffmpeg works in this session only.
) else (
    echo Added to user PATH: !addPath!
)
exit /b

REM Re-read machine + user PATH into this session (winget updates the
REM registry but the current cmd session keeps the old PATH).
:refresh_path
set "sysPath="
set "refreshUserPath="
for /f "tokens=2*" %%A in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul ^| findstr /i "REG_"') do set "sysPath=%%B"
for /f "tokens=2*" %%A in ('reg query "HKCU\Environment" /v Path 2^>nul ^| findstr /i "REG_"') do set "refreshUserPath=%%B"
if defined sysPath (
    if defined refreshUserPath (
        set "PATH=!sysPath!;!refreshUserPath!"
    ) else (
        set "PATH=!sysPath!"
    )
)
exit /b

:run_ps
rem Groq Whisper large-v3-turbo -> SRT transcriber (single file).
rem Batch bootstrap: copy self to unique temp .ps1 (PS 5.1 -File needs .ps1 ext) and run it.
set "TEMP_PS1=%TEMP%\groq_%RANDOM%_%RANDOM%.ps1"
copy /y "%~f0" "%TEMP_PS1%" >nul 2>&1
set "GROQ_SCRIPT_DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP_PS1%" %*
set "EC=%ERRORLEVEL%"
del /f /q "%TEMP_PS1%" >nul 2>&1
rem Keep the window open when launched from Explorer (double-click / drag-drop)
rem so the result stays readable. Terminal launches are unaffected.
set "DO_PAUSE=0"
echo %cmdcmdline% | findstr /i /c:"%~nx0" >nul 2>&1
if not errorlevel 1 set "DO_PAUSE=1"
if defined GROQ_NOPAUSE set "DO_PAUSE=0"
if "%DO_PAUSE%"=="1" (echo. & echo Finished with exit code %EC%. & pause)
exit /b %EC%
#>
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$RawArgs
)

$ErrorActionPreference = 'Stop'

# ---------------- script location (.env lives beside the script) ----------------
# Batch bootstrap sets GROQ_SCRIPT_DIR=%~dp0 before invoking PowerShell,
# because this file copies itself to %TEMP% and $PSScriptRoot would point there.
$Script:ScriptDir = ''
if ($env:GROQ_SCRIPT_DIR -ne $null -and $env:GROQ_SCRIPT_DIR.Trim() -ne '') { $Script:ScriptDir = $env:GROQ_SCRIPT_DIR.Trim() }
try {
  if ($Script:ScriptDir -ne '' -and (Test-Path -LiteralPath $Script:ScriptDir)) {
    $item = Get-Item -LiteralPath $Script:ScriptDir -ErrorAction SilentlyContinue
    if ($item -ne $null -and -not ($item -is [IO.DirectoryInfo])) { $Script:ScriptDir = [IO.Path]::GetDirectoryName($Script:ScriptDir) }
  } else {
    $Script:ScriptDir = (Get-Location).ProviderPath
  }
} catch {
  if ($Script:ScriptDir -eq '') { $Script:ScriptDir = (Get-Location).ProviderPath }
}
$Script:EnvFile = Join-Path $Script:ScriptDir '.env'

# ---------------- constants ----------------
$Script:Endpoint   = 'https://api.groq.com/openai/v1/audio/transcriptions'
$Script:LimitBytes = 24 * 1024 * 1024   # 24MB safety margin under Groq 25MB free-tier limit
$Script:ChunkSec   = 600                # 10-min chunks for large files
$Script:MaxRetries = 4
$Script:MaxWordSec = 2.0   # clamp: one word stamped longer is an alignment smear, not speech
$Script:AudioExts  = @('.flac', '.mp3', '.mp4', '.mpeg', '.mpga', '.m4a', '.ogg', '.wav', '.webm', '.mkv', '.avi', '.mov', '.wmv')

function Show-Help {
  Write-Host @'
subs-pipe.cmd - video/audio to .srt via Groq whisper-large-v3-turbo

MENU (double-click, no arguments):
  1. Ingest & Anonymize ... media -> upload\ as video_1.mp3 ...
  2. Transcribe & Restore .. Groq transcribes -> subtitles\, real names
  3. Restore Colab SRTs ..... Colab files -> subtitles\, real names

DIRECT (files/folders as arguments, drag-and-drop works too):
  subs-pipe.cmd <file-or-folder...> [options]
  subs-pipe.cmd "C:\Audio\talk.mp3" --lang en
  subs-pipe.cmd C:\Audio --recursive

OPTIONS:
  --lang CODE        ISO-639-1 language hint, e.g. en, es, de (default: auto-detect)
  --prompt TEXT      Style / spelling hint, max ~224 tokens. Same language as audio.
  --model NAME       Default: whisper-large-v3-turbo (also: whisper-large-v3)
  --outdir DIR       Write .srt files to DIR instead of next to input
  --max-line N       Max chars per subtitle line (default 42)
  --max-sec SEC      Max seconds per cue (default 5)
  --force            Re-transcribe even if .srt already exists and is newer
  --recursive        When given a folder, include subfolders
  --keep-json        Keep raw .verbose.json next to the .srt
  --dry-run          List what would be done, no upload
  --help             Show this help

API KEY (resolved in this order):
  1. --apikey KEY ..... 2. %GROQ_API_KEY% env var
  3. .env beside script   4. interactive prompt
  Get a free key at https://console.groq.com/keys (no card needed).
  It is asked once, then offered to save into .env.

LARGE FILES (>25MB free-tier limit):
  Needs ffmpeg once (press F in the menu).
  Audio is compressed to 16kHz mono 64k MP3, or split into 10-min
  chunks whose timestamps are stitched back together.
'@
}

function Get-DotEnvKey {
  try {
    if (-not (Test-Path -LiteralPath $Script:EnvFile)) { return '' }
    foreach ($line in (Get-Content -LiteralPath $Script:EnvFile -ErrorAction SilentlyContinue)) {
      if ($line -eq $null) { continue }
      $m = [regex]::Match($line, '^\s*GROQ_API_KEY\s*=\s*(.+?)\s*$')
      if ($m.Success) {
        $v = $m.Groups[1].Value.Trim().Trim('"').Trim("'").Trim()
        if ($v -ne '') { return $v }
      }
    }
  } catch {}
  return ''
}

function Resolve-ApiKey([string]$FlagKey) {
  if ($FlagKey -ne '') { return $FlagKey }
  if ($env:GROQ_API_KEY -ne $null -and $env:GROQ_API_KEY.Trim() -ne '') { return $env:GROQ_API_KEY.Trim() }
  $k = Get-DotEnvKey
  if ($k -ne '') { return $k }
  try {
    $sec = Read-Host -AsSecureString -Prompt 'Enter GROQ_API_KEY (input hidden)'
  } catch { $sec = $null }
  if ($sec -eq $null -or $sec.Length -eq 0) { return '' }
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr).Trim() }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Test-GroqKey([string]$Key) {
  Write-Host '  Checking API key (fast check, a few seconds)...'
  $tmp = [IO.Path]::GetTempFileName()
  try {
    & curl.exe --fail-with-body -sS -m 20 --connect-timeout 10 `
      -H ('Authorization: Bearer ' + $Key) `
      'https://api.groq.com/openai/v1/models' -o $tmp
    if ($LASTEXITCODE -eq 0) { Write-Host '  Key OK.' -ForegroundColor Green; return $true }
    $body = ''
    try { $body = Get-Content -LiteralPath $tmp -Raw -ErrorAction SilentlyContinue } catch { $body = '' }
    if ($body -eq $null) { $body = '' }
    if ($body -match 'invalid_api_key|Incorrect API key|unauthorized|\b401\b') {
      Write-Host '  Key INVALID (401). Get a free key at https://console.groq.com/keys' -ForegroundColor Red
      Write-Host '  If you pasted it at the prompt, check for a typo or extra spaces.' -ForegroundColor Yellow
      return $false
    }
    Write-Host '  Key check inconclusive (network hiccup?). Continuing - the upload will confirm.' -ForegroundColor Yellow
    return $true
  } finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  }
}

function Save-GroqKeyFile([string]$Key) {
  if ($env:GROQ_API_KEY -ne $null -and $env:GROQ_API_KEY.Trim() -ne '') { return }
  if ((Get-DotEnvKey) -ne '') { return }
  $ans = Read-Host -Prompt ("Save this key to $($Script:EnvFile) as GROQ_API_KEY=... so you only type it once? [Y/n]")
  if ($ans -eq '' -or $ans -match '^(?i)(y|yes)$') {
    try {
      $lines = @()
      if (Test-Path -LiteralPath $Script:EnvFile) { $lines = @(Get-Content -LiteralPath $Script:EnvFile -ErrorAction SilentlyContinue) }
      $out = @(); $found = $false
      foreach ($ln in $lines) {
        if (-not $found -and $ln -ne $null -and [regex]::IsMatch($ln, '^\s*GROQ_API_KEY\s*=')) { $out += ('GROQ_API_KEY=' + $Key); $found = $true }
        else { $out += $ln }
      }
      if (-not $found) { $out += ('GROQ_API_KEY=' + $Key) }
      if (-not (Test-Path -LiteralPath $Script:ScriptDir)) { New-Item -ItemType Directory -Path $Script:ScriptDir -Force | Out-Null }
      Set-Content -LiteralPath $Script:EnvFile -Value ($out -join "`r`n") -Encoding Ascii
      Write-Host ("  Saved to " + $Script:EnvFile) -ForegroundColor Green
    } catch {
      Write-Host ("  Could not save .env: " + $_.Exception.Message) -ForegroundColor Yellow
    }
  }
}

function Get-MimeType([string]$Ext) {
  $e = $Ext.ToLowerInvariant()
  if ($e -eq '.flac') { return 'audio/flac' }
  if ($e -eq '.mp3' -or $e -eq '.mpga') { return 'audio/mpeg' }
  if ($e -eq '.m4a') { return 'audio/mp4' }
  if ($e -eq '.mp4') { return 'video/mp4' }
  if ($e -eq '.mpeg') { return 'video/mpeg' }
  if ($e -eq '.ogg') { return 'audio/ogg' }
  if ($e -eq '.wav') { return 'audio/wav' }
  if ($e -eq '.webm') { return 'video/webm' }
  return 'application/octet-stream'
}

function Format-SrtTime([double]$Seconds) {
  if ($Seconds -lt 0) { $Seconds = 0 }
  $ts = [TimeSpan]::FromSeconds($Seconds)
  $totalH = [int][Math]::Floor($ts.TotalHours)
  return ('{0:D2}:{1:D2}:{2:D2},{3:D3}' -f $totalH, $ts.Minutes, $ts.Seconds, $ts.Milliseconds)
}

function Split-CueLines([string]$Text, [int]$MaxLine) {
  $t = $Text.Trim()
  if ($t.Length -le $MaxLine) { return @($t) }
  $mid = [int]($t.Length / 2)
  $best = -1; $bestScore = -1
  for ($i = 0; $i -lt $t.Length; $i++) {
    $c = $t[$i]
    if ($c -eq ' ' -or $c -eq ',' -or $c -eq ';' -or $c -eq '.' -or $c -eq '?' -or $c -eq '!' -or $c -eq '-') {
      if ($i -lt 4 -or $i -gt $t.Length - 4) { continue }
      $score = 0
      if ($c -ne ' ') { $score += 3 }
      if ($c -eq ',' -or $c -eq ';') { $score += 2 }
      $dist = [Math]::Abs($i - $mid)
      $score -= ($dist / 10.0)
      if ($score -gt $bestScore) { $bestScore = $score; $best = $i }
    }
  }
  if ($best -lt 0) {
    $best = $t.LastIndexOf(' ', [Math]::Min($MaxLine, $t.Length - 1))
    if ($best -lt 0) { $best = [Math]::Min($MaxLine, $t.Length - 1) }
  }
  $l1 = $t.Substring(0, $best + 1).Trim()
  $l2 = $t.Substring($best + 1).Trim()
  if ($l2 -eq '') { return @($l1) }
  if ($l2.Length -gt $MaxLine -and $l1.Length + 1 + $l2.Length -le ($MaxLine * 2)) {
    return @($l1, $l2)
  }
  if ($l2.Length -gt $MaxLine) {
    $l2 = $l2.Substring(0, $MaxLine).Trim()
  }
  return @($l1, $l2)
}

function Split-WordsToLines($Words, [int]$MaxLine) {
  if ($Words.Count -le 1) { return ,@($Words) }
  $lens = @(); $total = 0
  foreach ($wd in $Words) { $l = ([string]$wd.word).Length; $lens += $l; $total += $l }
  $total += ($Words.Count - 1)
  if ($total -le $MaxLine) { return ,@($Words) }
  $mid = $total / 2.0
  $best = -1; $bestScore = -1e12
  for ($k = 0; $k -lt ($Words.Count - 1); $k++) {
    $l1 = $k
    for ($m = 0; $m -le $k; $m++) { $l1 += $lens[$m] }
    $c = [string]$Words[$k].word
    $score = 0
    if ($c.EndsWith('.') -or $c.EndsWith('?') -or $c.EndsWith('!') -or $c.EndsWith(',') -or $c.EndsWith(';') -or $c.EndsWith(':') -or $c.EndsWith('-')) { $score += 3 }
    if ($c.EndsWith(',') -or $c.EndsWith(';')) { $score += 2 }
    $dist = [Math]::Abs($l1 - $mid)
    $score -= ($dist / 10.0)
    if ($score -gt $bestScore) { $bestScore = $score; $best = $k }
  }
  if ($best -lt 0) { $best = $Words.Count - 2 }
  $line1 = @($Words[0..$best]); $line2 = @($Words[($best + 1)..($Words.Count - 1)])
  if ($line2.Count -eq 0) { return ,@($Words) }
  return @($line1, $line2)
}

function Convert-WordsToCues($Words, [int]$MaxLine, [double]$MaxSec, [double]$MinSec) {
  $maxChars = [Math]::Min($MaxLine * 2, 60)
  $cues = [System.Collections.Generic.List[PSCustomObject]]::new()
  $cur = @()
  $curStart = 0.0
  $curLen = 0

  for ($i = 0; $i -lt $Words.Count; $i++) {
    $w = $Words[$i]
    $wtext = [string]$w.word
    if ($wtext -eq '' -and $w.text -ne $null) { $wtext = [string]$w.text }
    $wtext = $wtext.Trim()
    if ($wtext -eq '') { continue }
    $ws = [double]$w.start; $we = [double]$w.end
    if ($cur.Count -eq 0) {
      $cur = @(@{ word = $wtext; start = $ws; end = $we })
      $curStart = $ws; $curLen = $wtext.Length
      continue
    }
    $tentLen = $curLen + 1 + $wtext.Length
    $tentDur = $we - $curStart
    $prevText = [string]$cur[$cur.Count - 1].word
    $core = $prevText.TrimEnd('.').ToLowerInvariant()
    $isAbbrev = ($core -eq 'mr' -or $core -eq 'mrs' -or $core -eq 'ms' -or $core -eq 'dr' -or $core -eq 'st' -or $core -eq 'etc' -or $core -eq 'e.g' -or $core -eq 'i.e' -or $core -eq 'vs' -or $core -eq 'jr' -or $core -eq 'sr' -or $core -match '^\d')
    $endsSentence = (($prevText.EndsWith('.') -or $prevText.EndsWith('?') -or $prevText.EndsWith('!')) -and -not $isAbbrev)
    $endsClause = $prevText.EndsWith(',') -or $prevText.EndsWith(';') -or $prevText.EndsWith(':')
    $doFlush = $false
    if ($tentLen -gt $maxChars -or $tentDur -gt $MaxSec) { $doFlush = $true }
    elseif ($endsSentence) { $doFlush = $true }
    elseif ($endsClause -and $curLen -ge 40) { $doFlush = $true }
    if ($doFlush) {
      $cues.Add([PSCustomObject]@{ words = @($cur); start = $curStart; end = [double]$cur[$cur.Count - 1].end })
      $cur = @(@{ word = $wtext; start = $ws; end = $we })
      $curStart = $ws; $curLen = $wtext.Length
    } else {
      $cur += @{ word = $wtext; start = $ws; end = $we }
      $curLen = $tentLen
    }
  }
  if ($cur.Count -gt 0) {
    $cues.Add([PSCustomObject]@{ words = @($cur); start = $curStart; end = [double]$cur[$cur.Count - 1].end })
  }

  # NOTE (PS 5.1): assigning a NEW property to a PSCustomObject throws
  # ("property cannot be found") instead of adding it. Every cue object is
  # therefore constructed with ALL properties (words/start/end/text) here;
  # the loop below only adjusts existing ones, which is always legal.
  $lineCues = [System.Collections.Generic.List[PSCustomObject]]::new()
  foreach ($g in $cues) {
    $split = @(Split-WordsToLines $g.words $MaxLine)
    foreach ($ln in $split) {
      $lnArr = @($ln | Where-Object { $_ -ne $null })
      if ($lnArr.Count -eq 0) { continue }
      $firstStart = 0.0
      try { $firstStart = [double]$lnArr[0].start } catch { $firstStart = 0.0 }
      $lastEnd = $firstStart + 0.5
      try { $lastEnd = [double]$lnArr[$lnArr.Count - 1].end } catch { $lastEnd = $firstStart + 0.5 }
      if ($lastEnd -le $firstStart) { $lastEnd = $firstStart + 0.5 }
      $lineCues.Add([PSCustomObject]@{ words = $lnArr; start = $firstStart; end = $lastEnd; text = '' })
    }
  }

  for ($i = 0; $i -lt $lineCues.Count; $i++) {
    $c = $lineCues[$i]
    $text = (($c.words | ForEach-Object { $_['word'] }) -join ' ').Trim()
    $s = [double]$c.start; $e = [double]$c.words[$c.words.Count - 1].end
    if ($e -le $s) { $e = $s + 0.5 }
    $nextStart = 1e12
    if ($i + 1 -lt $lineCues.Count) { $nextStart = [double]$lineCues[$i + 1].start }
    if ($i -gt 0) {
      $prevEnd = [double]$lineCues[$i - 1].end
      if ($s -lt ($prevEnd + 0.04)) { $s = $prevEnd + 0.04; if ($e -le $s) { $e = $s + 0.2 } }
    }
    $dur = $e - $s
    if ($dur -lt $MinSec) {
      $e = [Math]::Min($s + $MinSec, $nextStart - 0.04)
      if ($e -le $s) { $e = $s + 0.2 }
    }
    $c.start = $s; $c.end = $e; $c.text = $text
  }
  return $lineCues
}

function Convert-SegmentsToCues($Segments, [int]$MaxLine, [double]$MaxSec) {
  $maxChars = $MaxLine * 2
  $out = [System.Collections.Generic.List[PSCustomObject]]::new()
  foreach ($sg in $Segments) {
    $s = [double]$sg.start; $e = [double]$sg.end
    $t = ([string]$sg.text).Trim()
    if ($t -eq '') { continue }
    if ($t.Length -le $maxChars -and ($e - $s) -le $MaxSec) {
      $out.Add([PSCustomObject]@{ start = $s; end = $e; text = $t })
      continue
    }
    $parts = @()
    $cur = ''
    foreach ($tok in ($t -split '\s+')) {
      if (($cur + ' ' + $tok).Trim().Length -gt $maxChars -and $cur -ne '') {
        $parts += $cur.Trim(); $cur = $tok
      } else { $cur = ($cur + ' ' + $tok).Trim() }
    }
    if ($cur.Trim() -ne '') { $parts += $cur.Trim() }
    $totalChars = 0; foreach ($p in $parts) { $totalChars += $p.Length }
    if ($totalChars -lt 1) { $totalChars = 1 }
    $dur = $e - $s; $cursor = $s
    for ($i = 0; $i -lt $parts.Count; $i++) {
      $frac = $parts[$i].Length / $totalChars
      $pe = $cursor + ($dur * $frac)
      if ($i -eq $parts.Count - 1) { $pe = $e }
      $out.Add([PSCustomObject]@{ start = $cursor; end = $pe; text = $parts[$i] })
      $cursor = $pe + 0.04
    }
  }
  return $out
}

function Write-SrtFile([string]$Path, $Cues, [int]$MaxLine) {
  $sb = New-Object Text.StringBuilder
  for ($i = 0; $i -lt $Cues.Count; $i++) {
    $c = $Cues[$i]
    $lines = Split-CueLines ([string]$c.text) $MaxLine
    [void]$sb.AppendLine(($i + 1).ToString())
    [void]$sb.AppendLine((Format-SrtTime ([double]$c.start)) + ' --> ' + (Format-SrtTime ([double]$c.end)))
    foreach ($ln in $lines) { [void]$sb.AppendLine($ln) }
    [void]$sb.AppendLine('')
  }
  $utf8bom = New-Object Text.UTF8Encoding($true)
  [IO.File]::WriteAllText($Path, $sb.ToString(), $utf8bom)
}

function Invoke-GroqTranscription([string]$AudioPath, [string]$Key, [string]$Model, [string]$Lang, [string]$Prompt, [string]$OutJson) {
  $curl = (Get-Command curl.exe -ErrorAction SilentlyContinue)
  if ($curl -eq $null) { throw 'curl.exe not found. It ships with Windows 10/11 in C:\Windows\System32.' }
  $ext = [IO.Path]::GetExtension($AudioPath)
  $mime = Get-MimeType $ext
  $fname = [IO.Path]::GetFileName($AudioPath)
  $hdrFile = [IO.Path]::GetTempFileName()
  try {
    $tries = 0; $delay = 5
    while ($true) {
      $tries++
      $curlArgs = @('--fail-with-body', '-sS', '-m', '600', '--connect-timeout', '20',
        '-H', ('Authorization: Bearer ' + $Key),
        '-F', ('file=@"' + $AudioPath + '";type=' + $mime + ';filename="' + $fname + '"'),
        '-F', ('model=' + $Model),
        '-F', 'response_format=verbose_json',
        '-F', 'timestamp_granularities[]=word',
        '-F', 'timestamp_granularities[]=segment',
        '-F', 'temperature=0.0',
        '-D', $hdrFile,
        '-o', $OutJson)
      if ($Lang -ne '') { $curlArgs += @('-F', ('language=' + $Lang)) }
      if ($Prompt -ne '') { $curlArgs += @('-F', ('prompt=' + $Prompt)) }
      $curlArgs += @($Script:Endpoint)
      & curl.exe @curlArgs
      $code = $LASTEXITCODE
      if ($code -eq 0) { return }
      $body = ''
      try { $body = (Get-Content -LiteralPath $OutJson -Raw -ErrorAction SilentlyContinue) } catch { $body = '' }
      if ($body -eq $null) { $body = '' }
      $isAuth = $body -match 'invalid_api_key|Incorrect API key|authentication|unauthorized'
      $isRate = ($body -match 'rate_limit|rate limit|429|try again') -or ($code -eq 28)
      $isServer = $body -match '500|502|503|504|overloaded|timeout'
      if ($isAuth) { throw ("Groq auth failed (401). Check your API key. Body: " + $body.Substring(0, [Math]::Min(300, $body.Length))) }
      if (($isRate -or $isServer) -and $tries -lt $Script:MaxRetries) {
        $wait = $delay
        try {
          $hdr = Get-Content -LiteralPath $hdrFile -Raw -ErrorAction SilentlyContinue
          $m = [regex]::Match($hdr, '(?im)^retry-after:\s*(\d+)')
          if ($m.Success) { $wait = [int]$m.Groups[1].Value + 1 }
        } catch {}
        Write-Host ("  Groq busy (try $tries/$($Script:MaxRetries)). Waiting ${wait}s...") -ForegroundColor Yellow
        Start-Sleep -Seconds $wait
        $delay = [Math]::Min($delay * 2, 60)
        continue
      }
      throw ("Groq upload failed (curl exit $code). Body: " + $body.Substring(0, [Math]::Min(500, $body.Length)))
    }
  } finally {
    Remove-Item -LiteralPath $hdrFile -Force -ErrorAction SilentlyContinue
  }
}

function Get-AudioFiles([string[]]$Paths, [bool]$Recurse) {
  $found = [System.Collections.Generic.List[string]]::new()
  foreach ($raw in $Paths) {
    $p = $raw.Trim().Trim('"').Trim("'")
    if ($p -eq '') { continue }
    if ((Test-Path -LiteralPath $p) -and ((Get-Item -LiteralPath $p) -is [IO.DirectoryInfo])) {
      $params = @{ LiteralPath = $p; File = $true; ErrorAction = 'SilentlyContinue' }
      if ($Recurse) { $params['Recurse'] = $true }
      $g = Get-ChildItem @params | Where-Object { $Script:AudioExts -contains $_.Extension.ToLowerInvariant() }
      foreach ($f in $g) { $found.Add($f.FullName) }
      continue
    }
    if (Test-Path -LiteralPath $p) {
      $found.Add((Get-Item -LiteralPath $p).FullName)
      continue
    }
    try {
      $resolved = Resolve-Path -Path $p -ErrorAction Stop
      foreach ($r in $resolved) {
        $it = Get-Item -LiteralPath $r.ProviderPath -ErrorAction SilentlyContinue
        if ($it -eq $null) { continue }
        if ($it -is [IO.DirectoryInfo]) {
          $params = @{ LiteralPath = $it.FullName; File = $true; ErrorAction = 'SilentlyContinue' }
          if ($Recurse) { $params['Recurse'] = $true }
          $g = Get-ChildItem @params | Where-Object { $Script:AudioExts -contains $_.Extension.ToLowerInvariant() }
          foreach ($f in $g) { $found.Add($f.FullName) }
        } else { $found.Add($it.FullName) }
      }
    } catch {
      Write-Host ("  skip (not found): " + $p) -ForegroundColor Yellow
    }
  }
  $seen = @{}
  $out = [System.Collections.Generic.List[string]]::new()
  foreach ($f in ($found | Sort-Object -Unique)) {
    $key = $f.ToLowerInvariant()
    if ($seen.ContainsKey($key)) { continue }
    $seen[$key] = $true
    $ext = [IO.Path]::GetExtension($f).ToLowerInvariant()
    if ($Script:AudioExts -notcontains $ext) {
      Write-Host ("  skip (unsupported type): " + $f) -ForegroundColor Yellow
      continue
    }
    $out.Add($f)
  }
  return $out.ToArray()
}

# ---------------- arg parsing (manual: files + --flags mix) ----------------
$OptLang = ''; $OptPrompt = ''; $OptModel = 'whisper-large-v3-turbo'
$OptOutDir = ''; $OptKey = ''
$OptMaxLine = 42; $OptMaxSec = 5.0; $OptMinSec = 1.0
$OptForce = $false; $OptRecurse = $false; $OptKeep = $false; $OptDry = $false
$FileInputs = @()
if ($RawArgs -eq $null) { $RawArgs = @() }
$i = 0
while ($i -lt $RawArgs.Count) {
  $a = [string]$RawArgs[$i]
  if ($a -eq '--') { $i++; while ($i -lt $RawArgs.Count) { $FileInputs += $RawArgs[$i]; $i++ }; break }
  elseif ($a -eq '--help' -or $a -eq '-h' -or $a -eq '/?' -or $a -eq '-Help') { Show-Help; exit 0 }
  elseif ($a -eq '--force' -or $a -eq '-f') { $OptForce = $true }
  elseif ($a -eq '--recursive' -or $a -eq '-r') { $OptRecurse = $true }
  elseif ($a -eq '--keep-json' -or $a -eq '-k') { $OptKeep = $true }
  elseif ($a -eq '--dry-run') { $OptDry = $true }
  elseif ($a -match '^(--lang|-l)(=(.*))?$') {
    if ($Matches[3] -ne $null) { $OptLang = $Matches[3] } else { $i++; $OptLang = [string]$RawArgs[$i] }
  }
  elseif ($a -match '^(--prompt|-p)(=(.*))?$') {
    if ($Matches[3] -ne $null) { $OptPrompt = $Matches[3] } else { $i++; $OptPrompt = [string]$RawArgs[$i] }
  }
  elseif ($a -match '^--model(=(.*))?$') {
    if ($Matches[2] -ne $null) { $OptModel = $Matches[2] } else { $i++; $OptModel = [string]$RawArgs[$i] }
  }
  elseif ($a -match '^--apikey(=(.*))?$') {
    if ($Matches[2] -ne $null) { $OptKey = $Matches[2] } else { $i++; $OptKey = [string]$RawArgs[$i] }
  }
  elseif ($a -match '^--outdir(=(.*))?$') {
    if ($Matches[2] -ne $null) { $OptOutDir = $Matches[2] } else { $i++; $OptOutDir = [string]$RawArgs[$i] }
  }
  elseif ($a -match '^--max-line(=(.*))?$') {
    if ($Matches[2] -ne $null) { $OptMaxLine = [int]$Matches[2] } else { $i++; $OptMaxLine = [int]$RawArgs[$i] }
  }
  elseif ($a -match '^--max-sec(=(.*))?$') {
    if ($Matches[2] -ne $null) { $OptMaxSec = [double]$Matches[2] } else { $i++; $OptMaxSec = [double]$RawArgs[$i] }
  }
  elseif ($a.StartsWith('-') -and $a.Length -gt 1 -and -not (Test-Path -LiteralPath $a)) {
    Write-Host ("Unknown option: " + $a) -ForegroundColor Red
    Show-Help; exit 2
  }
  else { $FileInputs += $a }
  $i++
}

if ($RawArgs.Count -gt 0) {
  Write-Host ("Inputs: {0}." -f $RawArgs.Count)
}
if ($FileInputs.Count -eq 0) {
  $ans = Read-Host -Prompt 'Drop a file/folder path (or type --help)'
  if ($ans -eq '--help' -or $ans -eq '-h') { Show-Help; exit 0 }
  if ($ans.Trim() -ne '') { $FileInputs = @($ans) }
}
if ($FileInputs.Count -eq 0) { Show-Help; exit 2 }
if ($OptOutDir -ne '' -and -not (Test-Path -LiteralPath $OptOutDir)) {
  New-Item -ItemType Directory -Path $OptOutDir -Force | Out-Null
}

$files = Get-AudioFiles $FileInputs $OptRecurse
if ($files.Count -eq 0) { Write-Host 'No supported audio/video files found.' -ForegroundColor Red; exit 2 }

Write-Host ("Found {0} file(s)." -f $files.Count)
foreach ($f in $files) { Write-Host ("  - " + $f) }

$Key = ''
if (-not $OptDry) {
  $Key = Resolve-ApiKey $OptKey
  if ($Key -eq '') {
    Write-Host 'Missing GROQ_API_KEY. Pass --apikey, set $env:GROQ_API_KEY, create .env beside the script with GROQ_API_KEY=..., or type it at the prompt.' -ForegroundColor Red
    Write-Host 'Get one free at https://console.groq.com/keys' -ForegroundColor Yellow
    exit 2
  }
  if (-not (Test-GroqKey $Key)) { exit 2 }
  Save-GroqKeyFile $Key
}

$ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
if ($ffmpeg -eq $null) {
  Write-Host 'NOTE: ffmpeg not found. Files >24MB will fail. Press F in the menu or run: winget install -e --id Gyan.FFmpeg' -ForegroundColor Yellow
}

$ok = 0; $fail = 0; $skip = 0; $n = 0
$createdSrts = @()
foreach ($audio in $files) {
  $n++
  $base = [IO.Path]::GetFileNameWithoutExtension($audio)
  $dir = [IO.Path]::GetDirectoryName($audio)
  if ($OptOutDir -ne '') { $dir = $OptOutDir }
  $srt = Join-Path $dir ($base + '.srt')
  Write-Host ''
  Write-Host ("[{0}/{1}] {2}" -f $n, $files.Count, $audio) -ForegroundColor Cyan
  if ((Test-Path -LiteralPath $srt) -and -not $OptForce) {
    $srtTime = (Get-Item -LiteralPath $srt).LastWriteTime
    $auTime = (Get-Item -LiteralPath $audio).LastWriteTime
    if ($srtTime -ge $auTime) { Write-Host '  skip: .srt exists and is newer (use --force to redo)'; $skip++; continue }
  }
  $size = (Get-Item -LiteralPath $audio).Length
  Write-Host ("  size: {0:N1} MB" -f ($size / 1MB))

  if ($OptDry) { Write-Host '  dry-run: would upload + write .srt'; continue }

  $workDir = Join-Path ([IO.Path]::GetTempPath()) ('groq_' + [IO.Path]::GetRandomFileName())
  New-Item -ItemType Directory -Path $workDir -Force | Out-Null
  try {
    # ---- build list of (path, offset) uploads ----
    $uploads = @()
    if ($size -le $Script:LimitBytes) {
      $uploads += @{ path = $audio; offset = 0.0 }
    } else {
      if ($ffmpeg -eq $null) { throw 'File exceeds 25MB free-tier limit and ffmpeg is missing. Press F in the menu or run: winget install -e --id Gyan.FFmpeg' }
      Write-Host '  large file: compressing directly to 16kHz mono 64k MP3...' -ForegroundColor Yellow
      $mp3 = Join-Path $workDir 'small.mp3'
      & ffmpeg -y -v error -i $audio -ar 16000 -ac 1 -map 0:a -c:a libmp3lame -b:a 64k $mp3
      if ((Test-Path -LiteralPath $mp3) -and ((Get-Item -LiteralPath $mp3).Length -le $Script:LimitBytes)) {
        Write-Host '  compressed to 64k MP3 fits, using it.'
        $uploads += @{ path = $mp3; offset = 0.0 }
      } else {
        Write-Host ("  splitting into ~{0}s chunks..." -f $Script:ChunkSec) -ForegroundColor Yellow
        $pat = Join-Path $workDir 'chunk_%03d.mp3'
        & ffmpeg -y -v error -i $audio -ar 16000 -ac 1 -map 0:a -c:a libmp3lame -b:a 64k -f segment -segment_time $Script:ChunkSec $pat
        $chunks = Get-ChildItem -LiteralPath $workDir -Filter 'chunk_*.mp3' | Sort-Object Name
        if ($chunks.Count -eq 0) { throw 'ffmpeg chunking produced no files.' }
        $off = 0.0
        foreach ($c in $chunks) { $uploads += @{ path = $c.FullName; offset = $off; placeholder = $true }; $off += $Script:ChunkSec }
        $uploads[0].offset = 0.0
      }
    }

    # ---- transcribe each upload, collect words and segments with offset ----
    $allWords = [System.Collections.Generic.List[PSCustomObject]]::new()
    $allSegments = [System.Collections.Generic.List[PSCustomObject]]::new()
    $realOffset = 0.0; $chunkIdx = 0
    $lastJson = $null
    foreach ($u in $uploads) {
      if ($u.ContainsKey('placeholder')) {
        $u.offset = $realOffset
      }
      $usize = 0; try { $usize = (Get-Item -LiteralPath $u.path).Length } catch { $usize = 0 }
      Write-Host ("  uploading: {0} ({1:N1} MB)" -f [IO.Path]::GetFileName($u.path), ($usize / 1MB))
      Write-Host '  (working... silence while Groq transcribes is normal, can take minutes for long audio)'
      $resp = Join-Path $workDir ('resp_' + $chunkIdx + '.json')
      Invoke-GroqTranscription $u.path $Key $OptModel $OptLang $OptPrompt $resp
      $j = Get-Content -LiteralPath $resp -Raw | ConvertFrom-Json
      $lastJson = $j
      if ($OptKeep) {
        $keepName = Join-Path $dir ($base + '.verbose.json')
        Copy-Item -LiteralPath $resp -Destination $keepName -Force
      }
      $dur = 0.0
      if ($j.duration -ne $null) { $dur = [double]$j.duration }
      elseif ($j.segments -ne $null -and $j.segments.Count -gt 0) { $dur = [double]$j.segments[$j.segments.Count - 1].end }
      if ($dur -le 0) { $dur = $Script:ChunkSec }
      
      # Accumulate segments with running offset for reliable fallback across chunks
      if ($j.segments -ne $null) {
        foreach ($sg in $j.segments) {
          $sOff = [double]$sg.start + [double]$u.offset
          $eOff = [double]$sg.end + [double]$u.offset
          $allSegments.Add([PSCustomObject]@{ start = $sOff; end = $eOff; text = [string]$sg.text })
        }
      }

      $ws = $null
      if ($j.words -ne $null) { $ws = $j.words }
      if ($ws -ne $null) {
        foreach ($w in $ws) {
          $nm = ''
          if ($w.word -ne $null) { $nm = [string]$w.word } elseif ($w.text -ne $null) { $nm = [string]$w.text } else { continue }
          $ws2 = [double]$w.start + [double]$u.offset; $we2 = [double]$w.end + [double]$u.offset
          if ($we2 -gt ($ws2 + $Script:MaxWordSec)) { $we2 = $ws2 + $Script:MaxWordSec }
          $allWords.Add([PSCustomObject]@{ word = $nm; start = $ws2; end = $we2 })
        }
      }
      $realOffset = [double]$u.offset + $dur
      $chunkIdx++
      if ($uploads.Count -gt 1) { Start-Sleep -Seconds 2 }
    }

    # ---- build cues ----
    $cues = @()
    if ($allWords.Count -gt 0) {
      $cues = Convert-WordsToCues $allWords $OptMaxLine $OptMaxSec $OptMinSec
    } elseif ($allSegments.Count -gt 0) {
      $cues = Convert-SegmentsToCues $allSegments $OptMaxLine $OptMaxSec
    } else {
      throw 'Groq returned no words/segments.'
    }
    if ($cues.Count -eq 0) { throw 'No subtitle cues generated (empty transcription?).' }
    Write-SrtFile $srt $cues $OptMaxLine
    $createdSrts += $srt
    Write-Host ("  SRT READY: " + $srt + (" ({0} cues)" -f $cues.Count)) -ForegroundColor Green
    $ok++
    Start-Sleep -Milliseconds 800
  } catch {
    Write-Host ("  FAIL: " + $_.Exception.Message) -ForegroundColor Red
    try {
      $stLine = ([string]$_.ScriptStackTrace -split "`r?`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1)
      if ($stLine -ne $null -and $stLine.Trim() -ne '') { Write-Host ("  at: " + $stLine.Trim()) -ForegroundColor Yellow }
    } catch {}
    $fail++
  } finally {
    Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}

Write-Host ''
Write-Host ("Done: {0} ok, {1} failed, {2} skipped." -f $ok, $fail, $skip)
if ($ok -gt 0 -and $createdSrts.Count -gt 0) {
  Write-Host 'SRT files ready:' -ForegroundColor Green
  foreach ($s in $createdSrts) { Write-Host ("  - " + $s) -ForegroundColor Green }
}
if ($fail -gt 0) { exit 1 } else { exit 0 }
