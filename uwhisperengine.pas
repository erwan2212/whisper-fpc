unit uWhisperEngine;

{
Résumé du flux :
Engine (Mémoire) -> Thread (Transport) -> Callback (Affichage/Incrémentation) -> Main/Timer (Mise à jour de la Mémoire).
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, whisper, whisper_api, uwhisperthread;

type
  TProgressEvent = procedure(Percent: Integer) of object;
  TWhisperDoneEvent = procedure(Sender: TObject) of object;
  TLogEvent = procedure(const AMsg: string) of object;

  TWhisperEngine = class
  private
    FTotalSegmentCount: Integer; // stocke le "Score Global" qui survit à la destruction des threads
    FTotalTimeOffset: Single; // Stocke le temps cumulé en secondes
    FCurrentThread: TWhisperThread;
    FOnProgress: TProgressEvent;
    FOnFinished: TWhisperDoneEvent;
    FOnLog: TLogEvent;
    FLastLang: AnsiString; // Pour garantir la persistance du PChar
    function GetParamsFromPreset(PresetIdx: Integer; const Lang: string; Threads: Integer): whisper_full_params;
  public
    constructor Create;
    destructor Destroy; override;

    // Une méthode pour remettre à zéro quand on clique sur "Start"
    procedure ResetSession;
    //
    procedure AddSegments(ACount: Integer; ADuration: Single); // On ajoute la durée
    property TotalTimeOffset: Single read FTotalTimeOffset;
    property TotalSegmentCount: Integer read FTotalSegmentCount;

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

    // Cette méthode sera appelée par les autres classes
    procedure Log(const AMsg: string);
    // Cette propriété sera reliée à ton Memo dans le formulaire principal
    property OnLog: TLogEvent read FOnLog write FOnLog;

    property CurrentThread: TWhisperThread read FCurrentThread;
    property OnProgress: TProgressEvent read FOnProgress write FOnProgress;
    property OnFinished: TWhisperDoneEvent read FOnFinished write FOnFinished;
  end;

implementation

procedure TWhisperEngine.ResetSession;
begin
  FTotalSegmentCount := 0;
  FTotalTimeOffset := 0; // Reset du temps
end;

procedure TWhisperEngine.AddSegments(ACount: Integer; ADuration: Single);
begin
  FTotalSegmentCount := FTotalSegmentCount + ACount;
  FTotalTimeOffset := FTotalTimeOffset + ADuration;
end;

constructor TWhisperEngine.Create;
begin
  FCurrentThread := nil;
end;

destructor TWhisperEngine.Destroy;
begin
  Stop;
  inherited;
end;

procedure TWhisperEngine.Log(const AMsg: string);
begin
  if Assigned(FOnLog) then
    FOnLog(AMsg);
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
    FTotalSegmentCount,
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
