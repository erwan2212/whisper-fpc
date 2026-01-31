unit uWhisperEngine;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, whisper, whisper_api, uwhisperthread;

type
  TProgressEvent = procedure(Percent: Integer) of object;
  TWhisperDoneEvent = procedure(Sender: TObject) of object;

  TWhisperEngine = class
  private
    FCurrentThread: TWhisperThread;
    FOnProgress: TProgressEvent;
    FOnFinished: TWhisperDoneEvent;
    FLastLang: AnsiString; // Pour garantir la persistance du PChar
    function GetParamsFromPreset(PresetIdx: Integer; const Lang: string; Threads: Integer): whisper_full_params;
  public
    constructor Create;
    destructor Destroy; override;

    procedure StartTranscription(
      const AModel: string;
      ASamples: PSingle;
      ASampleCount: Integer;
      PresetIdx: Integer;
      const ALang: string;
      const AThreads: string;
      const APrompt: string;
      const ASavePath: string;
      AGPU: Boolean
    );

    procedure Stop;

    property CurrentThread: TWhisperThread read FCurrentThread;
    property OnProgress: TProgressEvent read FOnProgress write FOnProgress;
    property OnFinished: TWhisperDoneEvent read FOnFinished write FOnFinished;
  end;

implementation

constructor TWhisperEngine.Create;
begin
  FCurrentThread := nil;
end;

destructor TWhisperEngine.Destroy;
begin
  Stop;
  inherited;
end;

function TWhisperEngine.GetParamsFromPreset(PresetIdx: Integer; const Lang: string; Threads: Integer): whisper_full_params;
begin
  case PresetIdx of
    0: Result := preset_perf;
    1: Result := preset_mid;
    2: Result := preset_qual;
  else
    Result := preset_mid;
  end;

  // Stockage persistant de la langue pour éviter que le PChar ne devienne invalide
  FLastLang := AnsiString(Lang);
  Result.language := PChar(FLastLang);
  Result.n_threads := Threads;
  Result.print_progress := 0;
end;

procedure TWhisperEngine.StartTranscription(const AModel: string; ASamples: PSingle;
  ASampleCount: Integer; PresetIdx: Integer; const ALang: string;
  const AThreads: string; const APrompt: string; const ASavePath: string; AGPU: Boolean);
var
  LocalParams: whisper_full_params;
begin
  // Sécurité de base
  if (ASamples = nil) or (ASampleCount <= 0) then Exit;

  Stop;

  LocalParams := GetParamsFromPreset(PresetIdx, ALang, StrToIntDef(AThreads, 4));

  FCurrentThread := TWhisperThread.Create(
    AModel,
    ASamples,
    ASampleCount,
    LocalParams,
    ASavePath,
    AGPU,
    0,
    APrompt
  );
end;

procedure TWhisperEngine.Stop;
begin
  if Assigned(FCurrentThread) then
  begin
    FCurrentThread.Terminate;

    if FCurrentThread.Finished then
      FreeAndNil(FCurrentThread)
    else
    begin
      // Le thread se détruira tout seul dès qu'il aura fini son cycle
      FCurrentThread.FreeOnTerminate := True;
      FCurrentThread := nil;
    end;
  end;
end;

end.
