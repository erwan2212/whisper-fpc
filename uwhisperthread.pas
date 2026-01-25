unit uWhisperThread;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, whisper;

type
  TWhisperProgressEvent = procedure(Percent: Integer) of object;
  TWhisperFinishedEvent = procedure(Sender: TObject) of object;


type
  TWhisperThread = class(TThread)
  private
    // --- Champs ---
    FModelPath: string;
    FSRTFile: string;
    FSamples: PSingle;
    FSampleCount: Integer;
    FParams: whisper_full_params;
    FCtxParams: TWhisperContextParams;
    FSegData: TSegmentData;

    FOnFinished: TWhisperFinishedEvent;
    //FOnProgress: TWhisperProgressEvent;
    //
    FProgressPercent: Integer;
    //procedure UpdateProgress;
    function GetIsTerminated: Boolean;
  protected
    procedure Execute; override;

    procedure DoFinished;

  public
    // On expose Terminated qui est normalement protected
    property IsCancelled: Boolean read GetIsTerminated;
    //
    property ProgressPercent: Integer read FProgressPercent;

    constructor Create(
      const AModelPath: string;
      ASamples: PSingle;
      ASampleCount: Integer;
      const AParams: whisper_full_params;
      const ASRTFile: string;
      const AUseGPU: Boolean=true;
      const AGPUDevice: Integer=0
    );
    destructor Destroy; override;

    // --- Events ---
    //property OnFinished: TWhisperFinishedEvent read FOnFinished write FOnFinished;
    //property OnProgress: TWhisperProgressEvent read FOnProgress write FOnProgress;
  end;



implementation

function TWhisperThread.GetIsTerminated: Boolean;
begin
  // Ici, à l'intérieur de l'implémentation, Terminated est parfaitement visible
  Result := Terminated;
end;

function WhisperAbortCallback(user_data: Pointer): Byte; cdecl;
begin
  if Assigned(user_data) and TWhisperThread(user_data).IsCancelled then
    Result := 1
  else
    Result := 0;
end;

function ProgressCallback(ctx: PWhisperContext; state: PWhisperState; progress: Integer; user_data: Pointer): Byte; cdecl;
var
  Thread: TWhisperThread;
begin
  Result := 1;
  if user_data = nil then Exit;
  Thread := TWhisperThread(user_data);

  // SI LE THREAD EST MARQUÉ COMME TERMINÉ, ON DIT À WHISPER DE S'ARRÊTER
    if Thread.Terminated then
    begin
      Result := 0; // 0 = Arrêt immédiat de whisper_full
      Exit;
    end;

  // On stocke juste la valeur, SANS Synchronize
  Thread.FProgressPercent := progress;
end;




constructor TWhisperThread.Create(
  const AModelPath: string;
  ASamples: PSingle;
  ASampleCount: Integer;
  const AParams: whisper_full_params;
  const ASRTFile: string;
  const AUseGPU: Boolean=true;
  const AGPUDevice: Integer=0
);
begin
  inherited Create(True); // suspended
  FreeOnTerminate := false;

  FModelPath   := AModelPath;
  FSamples     := ASamples;
  FSampleCount := ASampleCount;
  FParams      := AParams;

  FSRTfile:=ASRTFile;

  // --- callbacks ---
  FParams.new_segment_callback := @SegmentCallback;
  FParams.new_segment_callback_user_data := @FSegData;

  // Progress callback
  FParams.progress_callback := @ProgressCallback;
  FParams.progress_callback_user_data := Self; // passe le thread comme user_data

  // --- context params (GPU etc.) ---
  FCtxParams := whisper_context_default_params;
  FCtxParams.use_gpu := AUseGPU;
  FCtxParams.gpu_device := AGPUDevice;
  FCtxParams.flash_attn := True;

//  Start;
end;

procedure TWhisperThread.Execute;
var
  ctx: PWhisperContext;
begin
  ctx := nil;
  try
    ctx := whisper_init_from_file_with_params(
      PChar(FModelPath),
      FCtxParams
    );

    if ctx = nil then
      raise Exception.Create('Impossible de charger le modèle Whisper');

    // --- SRT ---
    AssignFile(FSegData.SRTFile, FSRTFile);
    Rewrite(FSegData.SRTFile);
    FSegData.SegmentIndex := 0;

    FParams.abort_callback := @WhisperAbortCallback;
    FParams.abort_callback_user_data := Self; // On passe l'instance du thread


    if whisper_full(ctx, FParams, FSamples, FSampleCount)<> 0 then raise Exception.Create('whisper_full: echec');


  finally
      // --- ÉTAPE CRUCIALE ---
      // On coupe les ponts avant de libérer le contexte
      FParams.new_segment_callback := nil;
      FParams.progress_callback := nil;

      if ctx <> nil then
        whisper_free(ctx);

      {$I-} CloseFile(FSegData.SRTFile); {$I+}
    end;
end;



procedure TWhisperThread.DoFinished;
begin
  if Assigned(FOnFinished) then
    FOnFinished(Self);
end;

destructor TWhisperThread.Destroy;
begin
  // Ferme le fichier SRT si ouvert
  {$I-}if TTextRec(FSegData.SRTFile).Mode <> 0 then CloseFile(FSegData.SRTFile);{$I+}
  // On s'assure que les pointeurs de callbacks sont mis à nil pour la DLL
    FParams.new_segment_callback := nil;
    FParams.progress_callback := nil;

    inherited Destroy;

end;



end.

