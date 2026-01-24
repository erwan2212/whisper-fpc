unit umain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ComCtrls, ExtCtrls, math, windows, whisper, sndfilefp, uwhisperthread;

type

  { Tfrmmain }

  Tfrmmain = class(TForm)
    Button1: TButton;
    btntranscribe: TButton;
    Button3: TButton;
    Button4: TButton;
    chklog: TCheckBox;
    txtaudio: TEdit;
    txtmodel: TEdit;
    Label1: TLabel;
    Label2: TLabel;
    Memo1: TMemo;
    OpenDialog1: TOpenDialog;
    ProgressBar1: TProgressBar;
    Timer1: TTimer;
    procedure Button1Click(Sender: TObject);
    procedure btntranscribeClick(Sender: TObject);
    procedure Button3Click(Sender: TObject);
    procedure Button4Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
  private
    procedure WhisperProgress(Percent: Integer);
    procedure WhisperFinished(Sender: Tobject);
  public

  end;


var
  frmmain: Tfrmmain;
  //
  ctx: PWhisperContext;
  cparams: TWhisperContextParams;
  globalparams: whisper_full_params;
  WAV_FILE :string= 'output.wav';
  MODEL_FILE:string = 'ggml-small.bin';
  segData: TSegmentData;
  Samples: array of Single;
  nSamples: Integer;
  start:int64;
  WhisperThread:tWhisperThread;
  WhisperLogBuffer: TStringList; // Le tampon de messages

implementation

{$R *.lfm}



{ Tfrmmain }

procedure MyWhisperLogCallback(level: Integer; const text: PChar; user_data: Pointer); cdecl;
  var
    S: string;
  begin
    // On stocke le log. Note: TStringList.Add est thread-safe en écriture simple ici
    if Assigned(WhisperLogBuffer) then
    begin
      S := TrimRight(string(text)); // Convertit en string et enlève les sauts de ligne à la fin
      if S <> '' then // N'ajoute pas de ligne si elle est devenue vide
        WhisperLogBuffer.Add(S);
    end;
  end;


procedure Tfrmmain.WhisperProgress(Percent: Integer);
begin
  ProgressBar1.Position := Percent;

end;

procedure Tfrmmain.WhisperFinished(Sender: Tobject);
begin
  try
      Memo1.Lines.Add('Transcription terminée !');
      Memo1.Lines.Add('Total: ' + FloatToStr((GetTickCount64 - start) / 1000) + ' s');
      ProgressBar1.Position := 100;

      if Assigned(WhisperThread) then
      begin
        // On attend une micro-seconde que le thread système soit totalement clos
        WhisperThread.WaitFor;
        FreeAndNil(WhisperThread);
      end;
    except
      on E: Exception do ; // On absorbe les éventuels derniers râles de la DLL
    end;



end;


procedure Tfrmmain.Button1Click(Sender: TObject);
begin

  {
  WriteLn('Initialisation Whisper (GPU ou CPU)…');
  ctx := whisper_init_from_file(PChar(MODEL_FILE));
  if ctx = nil then
  begin
    WriteLn('Erreur: impossible de charger le modèle.');
    Halt(1);
  end;
  }

  cparams := whisper_context_default_params;
  cparams.use_gpu := true;
  cparams.gpu_device := 0; // GPU 0
  cparams.flash_attn := True; // si supporté

  ctx := whisper_init_from_file_with_params(pchar(MODEL_FILE),cparams);
      if ctx = nil then
      begin
        memo1.lines.add('Erreur: impossible de charger le modèle.');
        Halt(1);
      end;

   globalparams:=preset_qual;
   globalparams.language :='en';

   {$i-}
   assignfile(segData.SRTFile ,WAV_FILE+'.srt');
   Rewrite(segData.SRTFile);
   {$i+}
   if IOResult <> 0 then memo1.lines.add('Erreur E/S : '+ inttostr(IOResult)); // gestion de l’erreur : message, fallback, abort, etc.

   // Callback pour afficher segments + timestamps
   globalparams.new_segment_callback := @SegmentCallback;
   globalparams.new_segment_callback_user_data := @segData;
   //params.progress_callback := @ProgressCallback;
   //params.progress_callback_user_data := nil;

   // Lecture WAV
   memo1.lines.add('Lecture WAV with libsndfile…');
   try
       ReadWavMono16kv2(WAV_FILE, Samples, nSamples);
   except
   on e:exception do
       begin
       memo1.lines.add(e.Message );
       exit;
       end;
   end;
   memo1.lines.add('Nombre d’échantillons : '+ inttostr(nSamples));
   if nSamples > 0 then memo1.lines.add('Premier échantillon : '+ floattostr(Samples[0]));

   // Transcription
   memo1.lines.add('Début transcription…');
   start:=gettickcount64;
   if whisper_full(ctx, globalparams, @Samples[0], nSamples) <> 0 then memo1.lines.add('Erreur lors de la transcription.');
   memo1.lines.add('Terminé.');
   memo1.lines.add('Total: ' + floattostr((GetTickCount64 - start) / 1000) + ' s');

   // Libération
   whisper_free(ctx);

   //
   {$i-}closefile(segData.SRTFile );{$i+}

end;

procedure Tfrmmain.btntranscribeClick(Sender: TObject);
var
  LocalParams: whisper_full_params;
begin
   //Timer1.Enabled := False; // Sécurité immédiate



  {
  if chklog.Enabled then
  begin
    WhisperLogBuffer := TStringList.Create;
    // On active le callback de log
    whisper_log_set(@MyWhisperLogCallback, nil);
  end;
  }

   memo1.Lines.Clear ;
   WAV_FILE:=txtaudio.Text ;
   MODEL_FILE:=txtmodel.Text ;
   // Lecture WAV
   memo1.lines.add('Lecture WAV with libsndfile…');
   try
       ReadWavMono16kv2(WAV_FILE, Samples, nSamples);
   except
   on e:exception do
       begin
       memo1.lines.add(e.Message );
       exit;
       end;
   end;
   memo1.lines.add('Nombre d’échantillons : '+ inttostr(nSamples));
   //if nSamples > 0 then memo1.lines.add('Premier échantillon : '+ floattostr(Samples[0]));

  LocalParams := preset_mid;
  LocalParams.language := 'en';

  WhisperThread:=TWhisperThread.Create(
    'ggml-base.bin',
    @samples[0],
    nSamples,
    LocalParams,
    'output.srt'
  );

  // assignation des callbacks
  //WhisperThread.OnProgress := @WhisperProgress;
  //WhisperThread.OnFinished := @WhisperFinished;
  //WhisperThread.OnTerminate :=@WhisperFinished; ;

  start:=gettickcount64;
  //Timer1.Enabled := True;
  WhisperThread.Start ;

end;

procedure Tfrmmain.Button3Click(Sender: TObject);
begin
  OpenDialog1.InitialDir :=GetCurrentDir ;
  OpenDialog1.Filter :='model|*.bin';;
  OpenDialog1.Execute ;
  txtmodel.Text :=OpenDialog1.FileName ;
end;

procedure Tfrmmain.Button4Click(Sender: TObject);
begin
  OpenDialog1.InitialDir :=GetCurrentDir ;
  OpenDialog1.Filter :='audio|*.wav';;
  OpenDialog1.Execute ;
  txtaudio.Text :=OpenDialog1.FileName ;
end;

procedure Tfrmmain.FormCreate(Sender: TObject);
begin
  SetExceptionMask([
    exInvalidOp,
    exDenormalized,
    exZeroDivide,
    exOverflow,
    exUnderflow,
    exPrecision
  ]);
  //
  txtmodel.Text :='ggml-small.bin';
  txtaudio.Text :='output.wav';
  //
  WhisperLogBuffer := TStringList.Create;
  // On active le callback de log
  whisper_log_set(@MyWhisperLogCallback, nil);
end;

procedure Tfrmmain.FormDestroy(Sender: TObject);
begin
  begin
  whisper_log_set(nil, nil); // Désactive le callback
  if Assigned(WhisperLogBuffer) then
    FreeAndNil(WhisperLogBuffer);
end;
end;

procedure Tfrmmain.Timer1Timer(Sender: TObject);
var
  LThread: TWhisperThread;
begin
  // 1. Protection contre l'appel du timer pendant la fermeture de l'appli
  if [csDestroying, csLoading] * ComponentState <> [] then Exit;

  // 2. Gestion sécurisée du Thread
  LThread := WhisperThread; // Copie locale de l'instance
  if Assigned(LThread) then
  begin
    try
      // On vérifie que l'objet est toujours valide en mémoire (bas niveau)
      if Pointer(LThread) <> nil then
        ProgressBar1.Position := LThread.ProgressPercent;

      if LThread.Finished then
      begin
        Timer1.Enabled := False;
        WhisperFinished(LThread);
      end;
    except
      // Si un crash survient ici, on coupe le timer pour arrêter l'hémorragie
      Timer1.Enabled := False;
      Exit;
    end;
  end;

  // 3. Gestion sécurisée des LOGS
  // On vérifie Assigned ET si la liste n'est pas en train d'être modifiée
  if Assigned(WhisperLogBuffer) then
  begin
    try
      if WhisperLogBuffer.Count > 0 then
      begin
        Memo1.Lines.BeginUpdate;
        try
          Memo1.Lines.AddStrings(WhisperLogBuffer);
          WhisperLogBuffer.Clear;
        finally
          Memo1.Lines.EndUpdate;
        end;
        SendMessage(Memo1.Handle, EM_SCROLLCARET, 0, 0);
      end;
    except
      // On ignore les erreurs de log pour ne pas stopper la transcription
    end;
  end;
end;


end.

