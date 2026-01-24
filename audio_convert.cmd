@echo off
setlocal

:: Vérifie si un fichier a été déposé
if "%~1"=="" (
    echo ERREUR : Glisse un fichier audio sur ce script.
    pause
    exit /b
)

:: Exécution de ffmpeg
:: %~dpn1 extrait le chemin et le nom sans l'extension pour créer la sortie
ffmpeg -i "%~1" -ar 16000 -ac 1 -c:a pcm_s16le "%~dpn1_whisper.wav"

echo.
echo Conversion terminee ! 
echo Fichier cree : "%~dpn1_whisper.wav"
echo.
pause