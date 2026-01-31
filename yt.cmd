@echo off
if "%~1"=="" (
    echo Usage: %~0 "URL"
    exit /b 1
)

set URL=%~1

rem yt-dlp.exe -x --audio-format wav --postprocessor-args "ffmpeg:-ar 16000" %URL%
yt-dlp.exe --extractor-args "youtube:player_client=android" -x --audio-format wav --postprocessor-args "ffmpeg:-ar 16000" %URL%
