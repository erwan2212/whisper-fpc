unit umain;

{$mode objfpc}{$H+}
{$R meta.res}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ComCtrls, ExtCtrls, math, windows, whisper, sndfilefp, uwhisperthread,
  ubassrecorder;

type

  { Tfrmmain }

  Tfrmmain = class(TForm)
    Button1: TButton;
    btntranscribe: TButton;
    btncapture: TButton;
    Button3: TButton;
    Button4: TButton;
    chklog: TCheckBox;
    chkgpu: TCheckBox;
    cmblang: TComboBox;
    cmbpreset: TComboBox;
    cmbdevices: TComboBox;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    Label6: TLabel;
    timer_capture: TTimer;
    txtaudio: TEdit;
    txtprompt: TEdit;
    txtmodel: TEdit;
    Label1: TLabel;
    Label2: TLabel;
    Memo1: TMemo;
    OpenDialog1: TOpenDialog;
    ProgressBar1: TProgressBar;
    timer_transcribe: TTimer;
    txtthreads: TEdit;
    procedure btncaptureClick(Sender: TObject);
    procedure btntranscribeClick(Sender: TObject);
    procedure Button3Click(Sender: TObject);
    procedure Button4Click(Sender: TObject);
    procedure chklogChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure timer_captureTimer(Sender: TObject);
    procedure timer_transcribeTimer(Sender: TObject);
  private
    FRecorder: TBassRecorder;
    FWhisperBuffer: array of Single; // Le buffer qui contient (Overlap + Nouveau bloc)
    FOverlapSize: Integer;          // 8000 pour 0.5s à 16kHz
    procedure WhisperProgress(Percent: Integer);
    procedure WhisperFinished(Sender: Tobject);
    //
    procedure HandleRecorderLog(const Msg: string);
    procedure OnAudioDataReceived(const Samples: array of Single); // Notre nouveau callback
    procedure listdevices;
    procedure DisplayTranscription(const AText: string);
    procedure UpdateMemoWithCleanerText(NewText: string);
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

procedure Tfrmmain.DisplayTranscription(const AText: string);
begin
  if AText = '' then Exit;

  Memo1.Lines.BeginUpdate;
  try
    // On ajoute l'heure et le texte
    Memo1.Lines.Add(Format('[%s] 🎤 %s', [FormatDateTime('HH:nn:ss', Now), AText]));
  finally
    Memo1.Lines.EndUpdate;
  end;

  // Scroll automatique vers le bas
  SendMessage(Memo1.Handle, EM_SCROLLCARET, 0, 0);
end;

procedure Tfrmmain.HandleRecorderLog(const Msg: string);
begin
  Memo1.Lines.Add(Format('[%s] [BASS] %s', [FormatDateTime('HH:nn:ss', Now), Msg]));
end;

procedure Tfrmmain.listdevices;
var
  DeviceList: TStringList;
  i: Integer;
begin


  FRecorder.OnLog := @HandleRecorderLog;
  FRecorder.OnAudioChunk := @OnAudioDataReceived;

  // Remplissage de la liste des périphériques
  DeviceList := FRecorder.GetLoopbackDevices;
  try
    cmbDevices.Items.Clear;
    for i := 0 to DeviceList.Count - 1 do
      cmbDevices.Items.AddObject(DeviceList[i], DeviceList.Objects[i]);

    if cmbDevices.Items.Count > 0 then
      cmbDevices.ItemIndex := 0; // Sélectionne le premier par défaut
  finally
    DeviceList.Free;
  end;
end;

procedure Tfrmmain.UpdateMemoWithCleanerText(NewText: string);
var
  LastLine: string;
  WordsNew: TStringList;
  i, MatchIdx: Integer;
  CleanText: string;
begin
  NewText := Trim(NewText);
  if NewText = '' then Exit;

  if Memo1.Lines.Count > 0 then
  begin
    // On récupère la toute dernière ligne affichée
    LastLine := LowerCase(Memo1.Lines[Memo1.Lines.Count - 1]);

    WordsNew := TStringList.Create;
    try
      WordsNew.Delimiter := ' ';
      WordsNew.StrictDelimiter := False;
      WordsNew.DelimitedText := NewText;

      // On cherche si les premiers mots du nouveau texte existent déjà
      // à la fin de la dernière ligne (on teste les 3 premiers mots)
      MatchIdx := 0;
      if WordsNew.Count >= 1 then
      begin
        // Si le 1er mot est dans les 20 derniers caractères de la dernière ligne
        if Pos(LowerCase(WordsNew[0]), LastLine) > (Length(LastLine) - 25) then MatchIdx := 1;

        // Si le 2ème mot suit, on décale encore
        if (WordsNew.Count >= 2) and (MatchIdx = 1) then
          if Pos(LowerCase(WordsNew[1]), LastLine) > 0 then MatchIdx := 2;
      end;

      // On reconstruit le texte sans les mots qui doublonnent
      CleanText := '';
      for i := MatchIdx to WordsNew.Count - 1 do
        CleanText := CleanText + WordsNew[i] + ' ';

      CleanText := Trim(CleanText);

      if CleanText <> '' then
        Memo1.Lines.Add('🎤 ' + CleanText);

    finally
      WordsNew.Free;
    end;
  end
  else
    Memo1.Lines.Add('🎤 ' + NewText);

  // Auto-scroll
  SendMessage(Memo1.Handle, EM_SCROLLCARET, 0, 0);
end;

//sans overlap buffer
{
procedure Tfrmmain.OnAudioDataReceived(const Samples: array of Single);
var
  LocalParams: whisper_full_params;
  MaxAmp: Single;
  i: Integer;
  SampleCount: Integer;
  Timestamp: string;
begin
  Timestamp := FormatDateTime('HH:nn:ss', Now);
  SampleCount := Length(Samples);

  if SampleCount = 0 then Exit;

  // 1. DIAGNOSTIC D'AMPLITUDE
  MaxAmp := 0;
  for i := 0 to SampleCount - 1 do
    if Abs(Samples[i]) > MaxAmp then MaxAmp := Abs(Samples[i]);

  // Retour visuel sur le volume d'entrée
  ProgressBar1.Position := Round(MaxAmp * 100);

  // Seuil de silence : On sort si c'est trop calme
  if MaxAmp < 0.001 then Exit;

  // 2. SÉCURITÉ ANTI-SATURATION
  // On vérifie si Whisper est déjà occupé par la tranche précédente
  if Assigned(WhisperThread) then
  begin
    // Si le thread n'a pas fini, on ignore cette tranche de 3s
    if not WhisperThread.Finished then Exit;

    // Si par hasard il a fini mais n'est pas encore libéré par le timer_capture,
    // on attend le prochain passage du timer pour ne pas créer de conflit.
    Exit;
  end;

  // 3. PRÉPARATION DES PARAMÈTRES (Adaptation selon ton UI)
  case cmbpreset.ItemIndex of
    0: LocalParams := preset_perf;
    1: LocalParams := preset_mid;
    2: LocalParams := preset_qual;
  else
    LocalParams := preset_mid;
  end;

  LocalParams.language := PChar(cmblang.Text);
  LocalParams.n_threads := StrToIntDef(txtthreads.Text, 4);
  LocalParams.print_progress := 0;

  Memo1.Lines.Add(Format('[%s] 🧠 Analyse flux live (%d samples)...', [Timestamp, SampleCount]));

  // 4. CRÉATION DU THREAD
  // Note : '' en 5ème paramètre car on ne veut pas de fichier SRT en mode live
  WhisperThread := TWhisperThread.Create(
    txtmodel.Text,
    @samples[0],
    SampleCount,
    LocalParams,
    '',
    chkgpu.Checked,
    0,
    txtPrompt.Text
  );

  // 5. LANCEMENT DU MOTEUR DE SURVEILLANCE CAPTURE
  start := GetTickCount64;
  timer_capture.Enabled := True; // C'est lui qui gérera l'affichage et la libération
  WhisperThread.Start;
end;
}

//avec overlap buffer
procedure Tfrmmain.OnAudioDataReceived(const Samples: array of Single);
var
  LocalParams: whisper_full_params;
  MaxAmp: Single;
  i: Integer;
  SampleCount: Integer;
  Timestamp: string;
  CombineCount: Integer;
begin
  Timestamp := FormatDateTime('HH:nn:ss', Now);
  SampleCount := Length(Samples);
  if SampleCount = 0 then Exit;

  // --- 1. GESTION DE L'OVERLAP (NOUVEAU) ---
  //OverlapSize := 8000; // 0.5 seconde à 16kHz

  // On combine ce qu'on a déjà dans le buffer avec les nouveaux arrivants
  CombineCount := Length(FWhisperBuffer) + SampleCount;
  SetLength(FWhisperBuffer, CombineCount);

  // On déplace les nouveaux samples à la suite de l'overlap existant
  // On utilise Move pour la rapidité (FPC 3.0 compatible)
  Move(Samples[0], FWhisperBuffer[CombineCount - SampleCount], SampleCount * SizeOf(Single));

  // --- 2. DIAGNOSTIC D'AMPLITUDE (sur les nouveaux samples uniquement) ---
  MaxAmp := 0;
  for i := 0 to SampleCount - 1 do
    if Abs(Samples[i]) > MaxAmp then MaxAmp := Abs(Samples[i]);

  ProgressBar1.Position := Round(MaxAmp * 100);

  // Seuil de silence
  if MaxAmp < 0.0015 then
  begin
    // Si c'est le silence, on vide quand même l'overlap pour ne pas
    // répéter un vieux mot quand le son reviendra dans 10 minutes.
    SetLength(FWhisperBuffer, 0);
    Exit;
  end;

  // --- 3. SÉCURITÉ ANTI-SATURATION ---
  if Assigned(WhisperThread) then
  begin
    if not WhisperThread.Finished then Exit;
    Exit;
  end;

  // --- 4. PRÉPARATION DES PARAMÈTRES ---
  case cmbpreset.ItemIndex of
    0: LocalParams := preset_perf;
    1: LocalParams := preset_mid;
    2: LocalParams := preset_qual;
  else
    LocalParams := preset_mid;
  end;

  LocalParams.language := PChar(cmblang.Text);
  LocalParams.n_threads := StrToIntDef(txtthreads.Text, 4);
  LocalParams.print_progress := 0;

  // Note : On loggue la taille COMBINÉE (Overlap + Nouveaux)
  //Memo1.Lines.Add(Format('[%s] 🧠 Analyse flux live (%d samples dont overlap)...', [Timestamp, CombineCount]));

  // --- 5. CRÉATION DU THREAD (On utilise FWhisperBuffer[0] !) ---
  WhisperThread := TWhisperThread.Create(
    txtmodel.Text,
    @FWhisperBuffer[0], // On pointe sur le buffer combiné
    CombineCount,
    LocalParams,
    '',
    chkgpu.Checked,
    0,
    txtPrompt.Text
  );

  // --- 6. PRÉPARATION DE L'OVERLAP POUR LE PROCHAIN TOUR ---
  // On ne garde que les 8000 derniers samples pour la prochaine fois
  if CombineCount > FOverlapSize then
  begin
    Move(FWhisperBuffer[CombineCount - FOverlapSize], FWhisperBuffer[0], FOverlapSize * SizeOf(Single));
    SetLength(FWhisperBuffer, FOverlapSize);
  end;

  start := GetTickCount64;
  timer_capture.Enabled := True;
  WhisperThread.Start;
end;

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

{
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
}

procedure Tfrmmain.WhisperFinished(Sender: Tobject);
  var
    SaveDlg: TSaveDialog;
  begin
    // Cette procédure est appelée par le Timer quand WhisperThread.Finished est vrai
    try
      if Assigned(WhisperThread) then
      begin

        // 1. Gestion des messages d'état
        if WhisperThread.IsCancelled then
          Memo1.Lines.Add('Transcription annulée par l''utilisateur.')
        else
        begin
          Memo1.Lines.Add('Transcription terminée !');
          Memo1.Lines.Add('Total: ' + FloatToStr((GetTickCount64 - start) / 1000) + ' s');
          ProgressBar1.Position := 100;
        end;

        // 2. LOGIQUE DE SECOURS (FALLBACK)
        // Si le fichier n'a pas pu être ouvert sur le disque mais qu'on a du texte en RAM
        if (not WhisperThread.IsCancelled) and (not WhisperThread.FileWasOpened) then
        begin
          if (WhisperThread.FullTextResult <> nil) and (WhisperThread.FullTextResult.Count > 0) then
          begin
            if MessageDlg('Erreur d''écriture',
               'Le fichier SRT n''a pas pu être créé sur le disque (accès refusé).' + sLineBreak +
               'Voulez-vous enregistrer le résultat manuellement ?',
               mtWarning, [mbYes, mbNo], 0) = mrYes then
            begin
              SaveDlg := TSaveDialog.Create(nil);
              try
                SaveDlg.DefaultExt := 'srt';
                SaveDlg.Filter := 'Fichiers SRT|*.srt|Tous les fichiers|*.*';
                SaveDlg.FileName := ExtractFileName(txtaudio.Text) + '.srt';
                if SaveDlg.Execute then
                  WhisperThread.FullTextResult.SaveToFile(SaveDlg.FileName);
              finally
                SaveDlg.Free;
              end;
            end;
          end;
        end;

        // 3. Libération propre
        WhisperThread.WaitFor;
        FreeAndNil(WhisperThread);
      end;
    finally
      // On remet TOUJOURS le bouton dans l'état initial, même en cas d'erreur
      btntranscribe.Caption := 'Transcribe';
      btntranscribe.Enabled := True;
      timer_transcribe.Enabled := False;
    end;
  end;

{
procedure main_nothread;
begin

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
   memo1.lines.add('Lecture WAV…');
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
}

procedure Tfrmmain.btntranscribeClick(Sender: TObject);
var
  LocalParams: whisper_full_params;
begin
   // --- LOGIQUE D'ARRÊT (STOP) ---
     if Assigned(WhisperThread) then
     begin
       btntranscribe.Enabled := False; // Désactive pour éviter les clics multiples pendant l'arrêt
       Memo1.Lines.Add('Demande d''arrêt en cours...');
       WhisperThread.Terminate; // Signal au thread qu'il doit s'arrêter
       Exit;
     end;

   memo1.Lines.Clear ;
   WAV_FILE:=txtaudio.Text ;
   MODEL_FILE:=txtmodel.Text ;
   // Lecture WAV
   memo1.lines.add('Lecture WAV…');
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


  case cmbpreset.ItemIndex of
  0:LocalParams := preset_perf;
  1:LocalParams := preset_mid;
  2:LocalParams := preset_qual;
  end;
  LocalParams.language := pchar(cmblang.Text) ; //'auto'
  LocalParams.n_threads:=strtoint(txtthreads.Text );


  Memo1.Lines.Add ('preset:'+inttostr(cmbpreset.ItemIndex));
  Memo1.Lines.Add ('language:'+LocalParams.language);
  Memo1.Lines.Add ('threads:'+inttostr(LocalParams.n_threads));



  //a revoir : initial_prompt

  WhisperThread:=TWhisperThread.Create(
    MODEL_FILE ,
    @samples[0],
    nSamples,
    LocalParams,
    'output.srt',chkgpu.Checked ,0,
    txtprompt.Text
  );

  btntranscribe.Caption := 'Stop';
  timer_transcribe.Enabled := True;
  start:=gettickcount64;

  WhisperThread.Start ;

end;

procedure Tfrmmain.btncaptureClick(Sender: TObject);
begin
  if btnCapture.Caption = 'Démarrer Capture' then
  begin
    if FRecorder.StartCapture(PtrInt(cmbDevices.Items.Objects[cmbDevices.ItemIndex]),10) then
    begin
      btnCapture.Caption := 'Stop Capture';
      Memo1.Lines.Add('🎤 Capture en cours...');
      // On peut activer le timer ici ou attendre le premier chunk audio
      timer_capture.Enabled := True;
      //
      FOverlapSize := 16000;// 1 sec
      SetLength(FWhisperBuffer, 0);
    end;
  end
  else
  begin
    FRecorder.StopCapture;
    btnCapture.Caption := 'Démarrer Capture';
    timer_capture.Enabled := False; // Arrêt définitif de la surveillance live
    Memo1.Lines.Add('🛑 Capture arrêtée.');
  end;
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

procedure Tfrmmain.chklogChange(Sender: TObject);
begin

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
  //
  FRecorder := TBassRecorder.Create;
  listdevices ;
end;

procedure Tfrmmain.FormDestroy(Sender: TObject);
begin
  begin
  whisper_log_set(nil, nil); // Désactive le callback
  if Assigned(WhisperLogBuffer) then
    FreeAndNil(WhisperLogBuffer);
end;
end;

procedure Tfrmmain.timer_captureTimer(Sender: TObject);
var
  LThread: TWhisperThread;
  FinalText: string;
  DureeTraitement: Double;
begin
  if [csDestroying, csLoading] * ComponentState <> [] then Exit;

  LThread := WhisperThread;

  if Assigned(LThread) then
  begin
    ProgressBar1.Position := LThread.ProgressPercent;

    if LThread.Finished then
    begin
      // 1. CALCUL DE PERFORMANCE
      // start a été capturé dans OnAudioDataReceived juste avant le thread.start
      DureeTraitement := (GetTickCount64 - start) / 1000;

      // 2. RÉCUPÉRATION DU TEXTE
      if Assigned(LThread.FullTextResult) and (LThread.FullTextResult.Count > 0) then
      begin
        FinalText := Trim(LThread.FullTextResult.Text);
        if FinalText <> '' then
        begin
          // On affiche le texte avec une petite info de perf en fin de ligne
          DisplayTranscription(Format('%s (⚡ %0.2fs)', [FinalText, DureeTraitement]));
          //DisplayTranscription(FinalText);
        end;
      end;
      //
      //UpdateMemoWithCleanerText(FinalText);
      // 3. NETTOYAGE
      LThread.WaitFor;
      FreeAndNil(WhisperThread);
      ProgressBar1.Position := 0;
    end;
  end;
end;

procedure Tfrmmain.timer_transcribeTimer(Sender: TObject);
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
        timer_transcribe.Enabled := False;
        WhisperFinished(LThread);
      end;
    except
      // Si un crash survient ici, on coupe le timer pour arrêter l'hémorragie
      timer_transcribe.Enabled := False;
      Exit;
    end;
  end;

  // 3. Gestion sécurisée des LOGS
  // On vérifie Assigned ET si la liste n'est pas en train d'être modifiée
  if Assigned(WhisperLogBuffer) and (chklog.Checked) then
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

