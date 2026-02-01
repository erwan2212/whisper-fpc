unit uAudioCapture;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, ubassrecorder, uWhisperEngine;

type
  TSingleArray = array of Single;

type
  TAudioCaptureManager = class
  private
    FRecorder: TBassRecorder;
    FEngine: TWhisperEngine;

    // Tes variables de gestion buffer/overlap
    FWhisperBuffer: TSingleArray;
    FOverlapSize: Integer;

    // Paramètres pour le thread
    FModelPath: string;
    FPresetIdx: Integer;
    FLang: string;
    FThreads: string;
    FPrompt: string;
    FUseGPU: Boolean;

    //wav variables
    FFileSamples: array of Single;
    FnFileSamples: Integer;

    // Callback interne pour BASS
    procedure OnAudioDataReceived(const Samples: array of Single);
  public
    constructor Create(AEngine: TWhisperEngine);
    destructor Destroy; override;

    // Méthode pour démarrer la capture avec tes paramètres
    function Start(DeviceIdx: Integer; const AModel, ALang, AThreads, APrompt: string;
                  Preset: Integer; UseGPU: Boolean): Boolean;
    procedure Stop;

    // Nouvelle méthode pour le mode fichier
    //function LoadWavFile(const AFileName: string; out ErrorMsg: string): Boolean; //uses sndfilefp
    function LoadWavFile2(const AFileName: string; out ErrorMsg: string): Boolean; //sans resampling
    function LoadWavFile3(const AFileName: string; out ErrorMsg: string): Boolean; //avec resampling

    // Propriétés pour exposer les données du fichier au moteur
    property FileSamples: TSingleArray read FFileSamples;
    property nFileSamples: Integer read FnFileSamples;

    property Recorder: TBassRecorder read FRecorder;
  end;

implementation

uses bass, bassmix, bass_aac{, sndfilefp};

constructor TAudioCaptureManager.Create(AEngine: TWhisperEngine);
begin
  FEngine := AEngine;
  FRecorder := TBassRecorder.Create;
  // On branche ton callback
  FRecorder.OnAudioChunk := @OnAudioDataReceived;
  FOverlapSize := 16000; // Ta valeur par défaut (1 sec à 16kHz)
  //
  BASS_PluginLoad(PChar(WideString('bass_aac.dll')), BASS_UNICODE);
end;

destructor TAudioCaptureManager.Destroy;
begin
  Stop;
  FRecorder.Free;
  inherited;
end;

procedure TAudioCaptureManager.OnAudioDataReceived(const Samples: array of Single);
var
  MaxAmp: Single;
  i: Integer;
  SampleCount: Integer;
  CombineCount: Integer;
begin
  SampleCount := Length(Samples);
  if SampleCount = 0 then Exit;

  // --- TON CODE D'OVERLAP EXACT ---
  CombineCount := Length(FWhisperBuffer) + SampleCount;
  SetLength(FWhisperBuffer, CombineCount);

  // Utilisation de Move pour la rapidité comme dans ton code
  Move(Samples[0], FWhisperBuffer[CombineCount - SampleCount], SampleCount * SizeOf(Single));

  // --- TON DIAGNOSTIC D'AMPLITUDE ---
  MaxAmp := 0;
  for i := 0 to SampleCount - 1 do
    if Abs(Samples[i]) > MaxAmp then MaxAmp := Abs(Samples[i]);

  // (Note : La gestion de la ProgressBar restera dans l'UI via le Timer ou un event)

  // Ton seuil de silence
  if MaxAmp < 0.0005 then //0.0015
  begin
    SetLength(FWhisperBuffer, 0);
    Exit;
  end;

  // --- TA SÉCURITÉ ANTI-SATURATION ---
  if Assigned(FEngine.CurrentThread) then
  begin
    if not FEngine.CurrentThread.Finished then Exit;
    // On ne fait rien de plus, le moteur gérera le nettoyage
  end;

  // --- TA PRÉPARATION DE L'ENGINE ---
  // On utilise l'engine pour créer le thread
  FEngine.StartTranscription(
    FModelPath,
    @FWhisperBuffer[0],
    CombineCount,
    FPresetIdx,
    FLang,
    FThreads,
    FPrompt,
    '', // Pas de SRT en live
    FUseGPU
  );

  // --- TA LOGIQUE DE DÉPLACEMENT D'OVERLAP ---
  if CombineCount > FOverlapSize then
  begin
    Move(FWhisperBuffer[CombineCount - FOverlapSize], FWhisperBuffer[0], FOverlapSize * SizeOf(Single));
    SetLength(FWhisperBuffer, FOverlapSize);
  end;

  // Lancement effectif
  // 2. On s'assure que l'index est synchronisé AVANT de démarrer le thread
    if Assigned(FEngine.CurrentThread) then
    begin
      // On force l'index de départ avec la valeur actuelle du réservoir de l'Engine
      FEngine.CurrentThread.SetStartSegmentIndex(FEngine.TotalSegmentCount);
      // Injection du temps cumulé
          FEngine.CurrentThread.SetTimeOffset(FEngine.TotalTimeOffset);

      // 3. SEULEMENT MAINTENANT on lance le thread
      FEngine.CurrentThread.Start;
    end;
end;

//resampling 16khz+mono
{
Formats Standards (Natif)
WAV : Tous les types (PCM, IEEE Float, etc.), y compris ceux avec des en-têtes complexes comme ceux de FFmpeg que nous avons corrigés.
MP3 : Couches 1, 2 et 3 (MPEG-1, MPEG-2).
MP2 / MP1 : Formats plus anciens.
OGG : Format Vorbis.
AIFF : Format standard d'Apple.
et AAC/M4A avec bass_aac
}
function TAudioCaptureManager.LoadWavFile3(const AFileName: string; out ErrorMsg: string): Boolean;
var
  Decoder: HSTREAM;
  Mixer: HSTREAM;
  Len: QWORD;
  Info: BASS_CHANNELINFO;
  Duration: Double;
  OrigFreq: Cardinal;
begin
  Result := False;
  ErrorMsg := '';

  // 1. On crée un décodeur simple (on garde BASS_UNICODE pour tes accents)
  Decoder := BASS_StreamCreateFile(0, PWideChar(WideString(AFileName)), 0, 0,
             BASS_STREAM_DECODE or BASS_UNICODE);

  if Decoder = 0 then
  begin
    ErrorMsg := 'Erreur BASS (Code ' + IntToStr(BASS_ErrorGetCode) + ')';
    Exit;
  end;

  try
    // --- RÉCUPÉRATION DES INFOS LOG ---
    // Fréquence d'origine
    BASS_ChannelGetInfo(Decoder, Info);
    OrigFreq := Info.freq;

    // 2. On crée un MIXER forcé en 16000Hz, Mono, Float
    // C'est ce Mixer qui va servir d'entonnoir parfait pour Whisper
    Mixer := BASS_Mixer_StreamCreate(16000, 1, BASS_STREAM_DECODE or BASS_SAMPLE_FLOAT);
    if Mixer = 0 then
    begin
      ErrorMsg := 'Erreur Mixer (Code ' + IntToStr(BASS_ErrorGetCode) + ')';
      Exit;
    end;

    // 3. On branche le fichier dans le mixer avec conversion de matrice (downmix mono automatique)
    if not BASS_Mixer_StreamAddChannel(Mixer, Decoder, BASS_MIXER_CHAN_DOWNMIX or BASS_MIXER_CHAN_NORAMPIN) then
    begin
      ErrorMsg := 'Erreur branchement Mixer.';
      Exit;
    end;

    // 4. On calcule la taille de sortie basée sur la durée réelle du décodeur
    Len := BASS_ChannelGetLength(Decoder, BASS_POS_BYTE);
    Duration := BASS_ChannelBytes2Seconds(Decoder, Len);
    FnFileSamples := Round(duration * 16000);

    SetLength(FFileSamples, FnFileSamples);

    //log
    if Assigned(FEngine) then
      FEngine.Log(Format('Source: %d Hz, %d canaux, Durée: %.2f s', [OrigFreq, Info.chans, Duration]));

    // 5. On pompe les données DEPUIS LE MIXER
    // Le mixer va forcer le resampling et le mono proprement
    if BASS_ChannelGetData(Mixer, @FFileSamples[0], FnFileSamples * SizeOf(Single)) = DWORD(-1) then
    begin
       ErrorMsg := 'Erreur de décodage via Mixer.';
       Exit;
    end;

    Result := True;
  finally
    // Libérer le mixer libère aussi les sources rattachées si on veut,
    // mais ici on libère les deux proprement.
    BASS_StreamFree(Mixer);
    BASS_StreamFree(Decoder);
  end;
end;

//ne gère pas le resampling à 16khz
function TAudioCaptureManager.LoadWavFile2(const AFileName: string; out ErrorMsg: string): Boolean;
var
  Stream: HSTREAM;
  Len: QWORD;
begin
  Result := False;
  ErrorMsg := '';

  // 1. Paramètre 1 passé à 0 (LongWord) au lieu de False
  // On ajoute BASS_ASYNCFILE pour plus de souplesse si besoin
  Stream := BASS_StreamCreateFile(0, PWideChar(WideString(AFileName)), 0, 0, BASS_STREAM_DECODE or BASS_SAMPLE_FLOAT);

  if Stream = 0 then
  begin
    ErrorMsg := 'Erreur BASS (Code ' + IntToStr(BASS_ErrorGetCode) + ') sur le fichier : ' + AFileName;
    Exit;
  end;

  try
    // --- OPTIONNEL MAIS CONSEILLÉ ---
    // Si tu veux forcer le Mono 16kHz via BASS au cas où le fichier source n'est pas bon
    // Stream := BASS_Mixer_StreamCreate(16000, 1, BASS_STREAM_DECODE or BASS_SAMPLE_FLOAT);
    // BASS_Mixer_StreamAddChannel(Stream, SourceStream, BASS_MIXER_CHAN_BUFFER);

    Len := BASS_ChannelGetLength(Stream, BASS_POS_BYTE);
    if Len = QWORD(-1) then
    begin
      ErrorMsg := 'Impossible de déterminer la taille du fichier.';
      Exit;
    end;

    FnFileSamples := Len div SizeOf(Single);
    SetLength(FFileSamples, FnFileSamples);

    // Extraction des données
    if BASS_ChannelGetData(Stream, @FFileSamples[0], Len) = DWORD(-1) then
    begin
       ErrorMsg := 'Erreur lors du décodage des données audio.';
       Exit;
    end;

    Result := True;
  finally
    BASS_StreamFree(Stream);
  end;
end;

// sndfilefp
{
function TAudioCaptureManager.LoadWavFile(const AFileName: string; out ErrorMsg: string): Boolean;
begin
  Result := False;
  ErrorMsg := '';
  try
    // Ta fonction de lecture habituelle
    ReadWavMono16kv2(AFileName, FFileSamples, FnFileSamples);
    Result := FnFileSamples > 0;
    if not Result then ErrorMsg := 'Le fichier est vide ou invalide.';
  except
    on E: Exception do
    begin
      FnFileSamples := 0;
      SetLength(FFileSamples, 0);
      ErrorMsg := E.Message; // On capture l'erreur exacte
    end;
  end;
end;
}

function TAudioCaptureManager.Start(DeviceIdx: Integer; const AModel, ALang, AThreads, APrompt: string;
                                   Preset: Integer; UseGPU: Boolean): Boolean;
begin
  FModelPath := AModel;
  FLang := ALang;
  FThreads := AThreads;
  FPrompt := APrompt;
  FPresetIdx := Preset;
  FUseGPU := UseGPU;

  Result := FRecorder.StartCapture(DeviceIdx, 10);
end;

procedure TAudioCaptureManager.Stop;
begin
  FRecorder.StopCapture;
  SetLength(FWhisperBuffer, 0);
end;

end.
