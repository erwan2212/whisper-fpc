unit ubassrecorder;

interface

uses
  SysUtils, Classes;

type
  TAmplitudeEvent = procedure(MaxAmp: Single) of object;
  TLogEvent = procedure(const Msg: string) of object;
  TAudioChunkEvent = procedure(const Samples: array of Single) of object;

  TBassRecorder = class
  private
    FOnAmplitude: TAmplitudeEvent;
    FOnLog: TLogEvent;
    FOnAudioChunk: TAudioChunkEvent;
    FInitialized: Boolean;
    FAccumulator: array of Single;
    FAccSize: Integer;
    FTargetSize: Integer;
    FCurrentFreq: Integer; // Pour savoir si on doit sous-échantillonner
    procedure Log(const Msg: string);
  public
    constructor Create;
    destructor Destroy; override;
    function GetLoopbackDevices: TStringList;
    function StartCapture(DeviceIndex: Integer; SecondsBuffer: Double = 5.0): Boolean;
    procedure StopCapture;
    property OnAmplitude: TAmplitudeEvent read FOnAmplitude write FOnAmplitude;
    property OnLog: TLogEvent read FOnLog write FOnLog;
    property OnAudioChunk: TAudioChunkEvent read FOnAudioChunk write FOnAudioChunk;
  end;

function WasapiCallback(Buffer: Pointer; Length: LongWord; User: Pointer): LongWord; stdcall;

implementation

uses bass, basswasapi;

const BASS_WASAPI_MONO=$100;

{
function WasapiCallback1(Buffer: Pointer; Length: LongWord; User: Pointer): LongWord; stdcall;
var
  Samples: PSingle;
  Count: Integer;
  Recorder: TBassRecorder;
  Max: Single;
  i: Integer;
begin
  if (Buffer <> nil) and (Length > 0) and (User <> nil) then
  begin
    Recorder := TBassRecorder(PtrInt(User));
    Samples := PSingle(Buffer);
    Count := Length div 4; // Nombre de samples reçus (Float 32 bits)

    // 1. CALCUL DE L'AMPLITUDE (VU-MÈTRE)
    if Assigned(Recorder.FOnAmplitude) then
    begin
      Max := 0;
      for i := 0 to Count - 1 do
        if Abs(Samples[i]) > Max then Max := Abs(Samples[i]);
      Recorder.FOnAmplitude(Max);
    end;

    // 2. ACCUMULATION AVEC SOUS-ÉCHANTILLONNAGE (Downsampling)
    // Si la carte est en 48000 et qu'on veut 16000, on prend 1 sample sur 3
    if Recorder.FCurrentFreq = 48000 then
    begin
      i := 0;
      while i < Count do
      begin
        SetLength(Recorder.FAccumulator, Recorder.FAccSize + 1);
        Recorder.FAccumulator[Recorder.FAccSize] := Samples[i];
        Inc(Recorder.FAccSize);
        Inc(i, 3); // On saute 2 samples sur 3
      end;
    end
    else
    begin
      // Cas standard ou déjà 16000 : copie intégrale
      i := Recorder.FAccSize;
      Recorder.FAccSize := Recorder.FAccSize + Count;
      SetLength(Recorder.FAccumulator, Recorder.FAccSize);
      Move(Samples^, Recorder.FAccumulator[i], Length);
    end;

    // 3. ENVOI À WHISPER
    // FTargetSize est maintenant basé sur 16000 Hz
    if (Recorder.FAccSize >= Recorder.FTargetSize) then
    begin
      if Assigned(Recorder.FOnAudioChunk) then
        Recorder.FOnAudioChunk(Recorder.FAccumulator);

      // Reset
      Recorder.FAccSize := 0;
      SetLength(Recorder.FAccumulator, 0);
    end;
  end;
  Result := 1;
end;
}

function WasapiCallback(Buffer: Pointer; Length: LongWord; User: Pointer): LongWord; stdcall;
var
  Samples: PSingle;
  Count, i, Step: Integer;
  Recorder: TBassRecorder;
  Info: BASS_WASAPI_INFO;
  //
  MaxAmp: Single;
  CurrentAmp: Single;
begin
  Result := 1;
  if (Buffer <> nil) and (Length > 0) and (User <> nil) then
  begin
    Recorder := TBassRecorder(User);
    Samples := PSingle(Buffer);
    Count := Length div 4; // Longueur en Float

    // --- DEBUT CALCUL AMPLITUDE ---
        if Assigned(Recorder.FOnAmplitude) then
        begin
          MaxAmp := 0;
          for i := 0 to Count - 1 do
          begin
            CurrentAmp := Abs(Samples[i]);
            if CurrentAmp > MaxAmp then MaxAmp := CurrentAmp;
          end;
          // On envoie la valeur maximale trouvée dans ce petit bloc
          Recorder.FOnAmplitude(MaxAmp);
        end;
        // --- FIN CALCUL AMPLITUDE ---

    BASS_WASAPI_GetInfo(Info);

    // Calcul du pas pour réduire à 16kHz
    // Info.chans est essentiel ici pour ne pas doubler les données
    Step := (Recorder.FCurrentFreq div 16000) * Info.chans;
    if Step < 1 then Step := 1;

    i := 0;
    while i < Count do
    begin
      // Gestion mémoire simplifiée pour FPC 3.0
      // On vérifie si on doit agrandir le tableau dynamique
      if Recorder.FAccSize >= System.Length(Recorder.FAccumulator) then
        SetLength(Recorder.FAccumulator, Recorder.FAccSize + 2000);

      Recorder.FAccumulator[Recorder.FAccSize] := Samples[i];
      Recorder.FAccSize := Recorder.FAccSize + 1;

      i := i + Step;
    end;

    // Envoi si le tampon est rempli
    if Recorder.FAccSize >= Recorder.FTargetSize then
    begin
      if Assigned(Recorder.FOnAudioChunk) then
      begin
        SetLength(Recorder.FAccumulator, Recorder.FAccSize);
        Recorder.FOnAudioChunk(Recorder.FAccumulator);
      end;
      Recorder.FAccSize := 0;
      SetLength(Recorder.FAccumulator, 0);
    end;
  end;
end;

constructor TBassRecorder.Create;
begin
  inherited Create;
  FAccSize := 0;
  FTargetSize := 16000 * 5; // Cible : 5 secondes à 16kHz
  FInitialized := BASS_Init(-1, 44100, 8, 0, nil);
  if not FInitialized and (BASS_ErrorGetCode() = 14) then FInitialized := True;
end;

destructor TBassRecorder.Destroy;
begin
  StopCapture;
  BASS_Free;
  inherited Destroy;
end;

procedure TBassRecorder.Log(const Msg: string);
begin
  if Assigned(FOnLog) then FOnLog(Msg);
end;

function TBassRecorder.GetLoopbackDevices: TStringList;
var
  i: Integer;
  info: BASS_WASAPI_DEVICEINFO;
begin
  Result := TStringList.Create;
  i := 0;
  while BASS_WASAPI_GetDeviceInfo(i, info) do
  begin
    if (info.flags and BASS_DEVICE_LOOPBACK <> 0) and (info.flags and BASS_DEVICE_ENABLED <> 0) then
      Result.AddObject(string(info.name), TObject(PtrInt(i)));
    Inc(i);
  end;
end;

function TBassRecorder.StartCapture(DeviceIndex: Integer; SecondsBuffer: Double = 5.0): Boolean;
var
  Info: BASS_WASAPI_INFO;
begin
  StopCapture;
  FAccSize := 0;
  SetLength(FAccumulator, 0);

  // Initialisation WASAPI (Mono + Autoformat)
  Result := BASS_WASAPI_Init(DeviceIndex, 0, 0,
              BASS_WASAPI_AUTOFORMAT or BASS_WASAPI_BUFFER or BASS_WASAPI_MONO,
              0.5, 0.05, @WasapiCallback, Self);

  if Result then
  begin
    BASS_WASAPI_GetInfo(Info);
    FCurrentFreq := Round(Info.freq);

    // TRÈS IMPORTANT : La cible pour Whisper est TOUJOURS 16000 Hz
    FTargetSize := Round(16000 * SecondsBuffer);

    if BASS_WASAPI_Start then
      Log(Format('Capture active: %d Hz -> Sortie Whisper: 16000 Hz (Buffer: %g s)', [FCurrentFreq, SecondsBuffer]))
    else
    begin
      BASS_WASAPI_Free;
      Result := False;
    end;
  end;
end;

procedure TBassRecorder.StopCapture;
begin
  BASS_WASAPI_Stop(True);
  BASS_WASAPI_Free;
  FAccSize := 0;
  SetLength(FAccumulator, 0);
end;

end.
