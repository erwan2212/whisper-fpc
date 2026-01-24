unit unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ComCtrls,
  ExtCtrls, Process,inifiles;

type

  { TTranscribeThread }

  TTranscribeThread = class(TThread)
  private
    FProcess: TProcess;
    FOnOutput: TNotifyEvent;
    FOnFinished: TNotifyEvent;
    FOwner: TObject;
    FBuffer: string;

    procedure DoOnOutput;
    procedure DoOnFinished;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TObject; const ACmd, AParams: string); reintroduce;
    destructor Destroy; override;

    property OnOutput: TNotifyEvent read FOnOutput write FOnOutput;
    property OnFinished: TNotifyEvent read FOnFinished write FOnFinished;
    property Buffer: string read FBuffer;

    // 🔥 indispensable pour tuer whisper-cli depuis le form
    property Process: TProcess read FProcess;
  end;



  { TForm1 }

  TForm1 = class(TForm)
    ButtonRun: TButton;
    ButtonBrowseModel: TButton;
    ButtonBrowseInput: TButton;
    ComboBox1: TComboBox;
    txtparams: TEdit;
    EditModel: TEdit;
    EditInput: TEdit;
    Langage: TLabel;
    LabelModel: TLabel;
    LabelInput: TLabel;
    lblparams: TLabel;
    MemoLog: TMemo;
    OpenDialog1: TOpenDialog;
    SaveDialog1: TSaveDialog;
    ProgressBar1: TProgressBar;
    TimerProgress: TTimer;
    procedure ButtonBrowseInputClick(Sender: TObject);
    procedure ButtonBrowseModelClick(Sender: TObject);
    procedure ButtonRunClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCloseQuery(Sender: TObject; var CanClose: boolean);
    procedure FormCreate(Sender: TObject);
    procedure TimerProgressTimer(Sender: TObject);
  private
    FThread: TTranscribeThread;
    DurationKnown :boolean;
    AudioDurationMS :integer;
    EstimatedTotal :integer;
    Elapsed :integer;
    procedure ProcessOutput(const Line: string);
    procedure ThreadOutput(Sender: TObject);
    procedure ThreadFinished(Sender: TObject);
    procedure AppendLog(const S: string);
    procedure SetUIRunning(const ARunning: Boolean);
  public

  end;




var
  Form1: TForm1;
  istart:int64=0;
  iend:int64=0;



implementation

{$R *.lfm}

function EstimateWhisperDurationMS(AudioMS: Integer; const ModelName: string): Integer;
begin
  if Pos('tiny', ModelName) > 0 then
    Result := AudioMS div 12
  else if Pos('base', ModelName) > 0 then
    Result := AudioMS div 6
  else if Pos('small', ModelName) > 0 then
    Result := AudioMS div 3
  else
    Result := AudioMS * 6; // fallback pour medium/large
end;



{ TTranscribeThread }

constructor TTranscribeThread.Create(AOwner: TObject; const ACmd, AParams: string);
var
  Parts: TStringList;
  I: Integer;
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FOwner := AOwner;

  FProcess := TProcess.Create(nil);
  FProcess.Executable := ACmd;
  FProcess.Options := [poUsePipes, poStderrToOutPut];
  FProcess.ShowWindow := swoHIDE;

  Parts := TStringList.Create;
  try
    Parts.Delimiter := ' ';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := AParams;
    for I := 0 to Parts.Count - 1 do
      if Parts[I] <> '' then
        FProcess.Parameters.Add(Parts[I]);
  finally
    Parts.Free;
  end;

  FProcess.Execute;
  Start;
end;

destructor TTranscribeThread.Destroy;
begin
  if Assigned(FProcess) then
  begin
    if FProcess.Running then
      FProcess.Terminate(0);
    FProcess.Free;
  end;
  inherited Destroy;
end;

procedure TTranscribeThread.DoOnOutput;
begin
  if Assigned(FOnOutput) then
    FOnOutput(FOwner);
end;

procedure TTranscribeThread.DoOnFinished;
begin
  if Assigned(FOnFinished) then
    FOnFinished(FOwner);
end;

procedure TTranscribeThread.Execute;
var
  LocalBuf: array[0..2047] of byte;
  BytesRead: Integer;
begin
  while not Terminated do
  begin
    if FProcess.Output.NumBytesAvailable > 0 then
    begin
      BytesRead := FProcess.Output.Read(LocalBuf, SizeOf(LocalBuf));
      if BytesRead > 0 then
      begin
        SetString(FBuffer, PChar(@LocalBuf[0]), BytesRead);
        Queue(@DoOnOutput);
      end;
    end

    else if not FProcess.Running then
      Break;

    Sleep(10);
  end;

  Queue(@DoOnFinished);
end;

{ TForm1 }

procedure TForm1.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  if Assigned(FThread) and (not FThread.Finished) then
  begin
    if MessageDlg('Une transcription est en cours. Quitter ?', mtConfirmation,
      [mbYes, mbNo], 0) = mrNo then
    begin
      CloseAction := caNone;
      Exit;
    end;
  end;
end;

procedure TForm1.FormCloseQuery(Sender: TObject; var CanClose: boolean);
begin
  if Assigned(FThread) then
begin
  if Assigned(FThread.Process) and FThread.Process.Running then
  begin
    FThread.Process.Terminate(0);
    Sleep(200);
    if FThread.Process.Running then
      FThread.Process.Terminate(1);
  end;

  FThread.Terminate;
  FThread.WaitFor;
  FreeAndNil(FThread);
end;

end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  ComboBox1.ItemIndex :=0;
  if FileExists ('ggml-base.bin') then EditModel.Text :='ggml-base.bin';

end;

procedure TForm1.TimerProgressTimer(Sender: TObject);
begin
  Elapsed := Elapsed + 100;

  if Elapsed < EstimatedTotal then
    ProgressBar1.Position := Elapsed
  else
    ProgressBar1.Position := ProgressBar1.Max;
end;


procedure TForm1.ButtonBrowseModelClick(Sender: TObject);
begin
  OpenDialog1.Filter := 'Whisper model|*.bin|Tous fichiers|*.*';
  if OpenDialog1.Execute then
    EditModel.Text := OpenDialog1.FileName;
end;

procedure TForm1.ButtonBrowseInputClick(Sender: TObject);
begin
  OpenDialog1.Filter := 'Audio|*.wav;*.mp3;*.flac;*.m4a;*.ogg|Tous fichiers|*.*';
  if OpenDialog1.Execute then
    EditInput.Text := OpenDialog1.FileName;
end;


//whisper-cli.exe -m "../ggml-base.bin" -f "../1971_Interview,_Bobbie_R._Allen,_Staff_Breakfast.wav" -osrt --language en --max-context 50 --beam-size 3 --temperature 0 --temperature-inc 0.2 --threads 8 --split-on-word

procedure TForm1.ButtonRunClick(Sender: TObject);
var
  Cmd,IniFileName: string;
  Params: string;
  ProfileParams: string;
  ini:TIniFile;
begin
  //
  istart:=gettickcount;
  iend:=0;
  DurationKnown := False;
AudioDurationMS := 0;
EstimatedTotal := 0;
Elapsed := 0;

  //
ProfileParams :=txtparams.text;
If pos('whisper-cli',cmd)>=0 then ProfileParams:=ProfileParams+'--language '+ComboBox1.Text +' ';


  if EditModel.Text = '' then
  begin
    ShowMessage('Modèle manquant');
    Exit;
  end;
  if EditInput.Text = '' then
  begin
    ShowMessage('Fichier d''entrée manquant');
    Exit;
  end;

  if Assigned(FThread) and (not FThread.Finished) then
  begin
    ShowMessage('Une transcription est déjà en cours.');
    Exit;
  end;

  MemoLog.Lines.Clear;
  ProgressBar1.Position := 0;

  // À adapter selon le nom de ton exécutable Whisper et ses options
  // Exemple avec whisper.cpp : main.exe
  Cmd := 'whisper-cli.exe';
  //if not FileExists (cmd) then cmd:='main.exe';


  // 2. Vérification si whisper-cli.exe existe dans le dossier courant
  if not FileExists(cmd) then
  begin
    // 3. Sinon, lecture du fichier config.ini
    IniFileName := IncludeTrailingPathDelimiter(GetCurrentDir) + 'config.ini';

    if not FileExists(IniFileName) then
    begin
      ShowMessage ('Erreur : config.ini introuvable.');
      Halt(1);
    end;

    Ini := TIniFile.Create(IniFileName);

      cmd := Ini.ReadString('main', 'exe', '');

      if cmd = '' then
      begin
        ShowMessage('Erreur : clé "exe" absente dans [main].');
        Halt(1);
      end;

      // Résout les chemins relatifs (. \)
      cmd := ExpandFileName(cmd);

      if not FileExists(cmd) then
      begin
        ShowMessage('Erreur : whisper-cli.exe introuvable');
        Halt(1);
      end;
      Ini.Free;
   end;


  // Exemple de params : --model ggml-base.bin --file "input.wav" --output-txt --output-file "output.txt"
  Params :=
    '--model "' + EditModel.Text + '" ' +
    '--file "' + EditInput.Text + '" ' +
    '--output-srt ';
    //If pos('whisper-cli',cmd)>=0 then params:=params+'--output-file "' + EditInput.Text + '.txt" ';
    params:=params + ProfileParams;

  FThread := TTranscribeThread.Create(Self, Cmd, Params);
  FThread.OnOutput := @ThreadOutput;
  FThread.OnFinished := @ThreadFinished;

  SetUIRunning(True);
  AppendLog('Commande : ' + Cmd + ' ' + Params);
end;

function ExtractDurationSec(const Line: string): Double;
var
  pStart, pEnd: Integer;
  DurationStr: string;
  FS: TFormatSettings;
begin
  Result := 0;

  // Cherche la fin " sec)"
  pEnd := Pos(' sec)', Line);
  if pEnd = 0 then
    Exit;

  // Cherche la dernière parenthèse ouvrante avant " sec)"
  pStart := LastDelimiter('(', Line);
  if (pStart = 0) or (pStart > pEnd) then
    Exit;

  // Extrait "21806059 samples, 1362.9"
  DurationStr := Copy(Line, pStart + 1, pEnd - pStart - 1);

  // On ne veut que la partie après la virgule
  // → "1362.9"
  if Pos(',', DurationStr) > 0 then
    DurationStr := Trim(Copy(DurationStr, Pos(',', DurationStr) + 1, MaxInt));

  // Force le séparateur décimal à '.'
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';

  // Convertit en float
  Result := StrToFloat(DurationStr, FS);
end;




procedure TForm1.ProcessOutput(const Line: string);
var
  p1, p2: Integer;
  DurationSecStr: string;
begin
  AppendLog(Line);

  // Cherche "(xxxx sec)"
  p1 := Pos(' sec)', Line);
  if p1 > 0 then
  begin
    p2 := LastDelimiter('(', Line);
    if p2 > 0 then
    begin
      DurationSecStr := Copy(Line, p2 + 1, p1 - p2 - 1);

      AudioDurationMS := Round(ExtractDurationSec(Line) * 1000);
      DurationKnown := True;

      // Estimation de la durée totale
      EstimatedTotal := EstimateWhisperDurationMS(AudioDurationMS, EditModel.Text);

      ProgressBar1.Position := 0;
      ProgressBar1.Max := EstimatedTotal;

      Elapsed := 0;
      TimerProgress.Enabled := True;
    end;
  end;
end;


procedure TForm1.ThreadOutput(Sender: TObject);
begin
  if Assigned(FThread) then
  begin
    // Tant que la durée n'est pas connue, on analyse la sortie
    if not DurationKnown then ProcessOutput(FThread.Buffer);
    //
    AppendLog(FThread.Buffer);
    //UpdateProgressFromLine(FThread.Buffer);
  end;
end;

procedure TForm1.ThreadFinished(Sender: TObject);
begin
  TimerProgress.Enabled := False;
  ProgressBar1.Position := ProgressBar1.Max; // 100%

  AppendLog('Transcription terminée.');
  iend:=gettickcount;
  AppendLog('elapsed='+inttostr((iend-istart) div 1000)) ;
  SetUIRunning(False);
end;


procedure TForm1.AppendLog(const S: string);
begin
  MemoLog.Lines.Add(TrimRight(S));
  MemoLog.SelStart := Length(MemoLog.Text);
  MemoLog.SelLength := 0;
end;



procedure TForm1.SetUIRunning(const ARunning: Boolean);
begin
  ButtonRun.Enabled := not ARunning;
  ButtonBrowseModel.Enabled := not ARunning;
  ButtonBrowseInput.Enabled := not ARunning;
end;

end.

