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
ffmpeg -i "%~1" -ar 16000 -ac 1 -c:a pcm_s16le -af "highpass=f=100, lowpass=f=12000, afftdn=nf=-30, equalizer=f=200:t=q:w=1:g=-6, equalizer=f=350:t=q:w=1:g=-4, acompressor=threshold=-20dB:ratio=4:attack=5:release=100:makeup=6, loudnorm=I=-16:LRA=7:TP=-1" "%~dpn1_whisper.wav"

echo.
echo Conversion terminee ! 
echo Fichier cree : "%~dpn1_whisper.wav"
echo.
pause