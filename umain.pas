unit umain;

{$mode objfpc}{$H+}
{$R meta.res}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ComCtrls, ExtCtrls, math, windows, whisper, whisper_api, uwhisperthread,
  ubassrecorder,uWhisperEngine,uAudioCapture;

{
//
whisper :
C'est le fichier d'en-tête (header) qui permet à Pascal de parler à la bibliothèque whisper.dll.
Il définit les structures de données (comme whisper_context) et les fonctions de base.

whisper_api :
C'est une couche de simplification.
Elle encapsule les appels complexes de la DLL pour offrir des fonctions plus faciles à utiliser en Pascal, comme l'initialisation du modèle et le lancement de la transcription avec des paramètres simplifiés.
//
uWhisperThread :
C'est l'ouvrier. Son rôle est d'exécuter la transcription en arrière-plan (dans un thread séparé).
Cela évite que ton application ne "gèle" (ne réponde plus) pendant que l'IA travaille.
Il prend les samples audio et génère le texte.

uWhisperEngine :
C'est le chef de chantier. Il gère le cycle de vie du moteur Whisper.
Il crée et détruit le thread, gère le chargement du fichier modèle (.bin) et sert de pont entre ton interface et l'ouvrier (le thread).
//
ubassrecorder :
C'est le spécialiste de la capture "Live".
Il utilise la bibliothèque BASS pour écouter le micro, découper le son en petits morceaux (chunks) et les envoyer au moteur en temps réel.
uAudioCapture :
C'est le gestionnaire de ressources audio.
C'est l'unité que nous venons de blinder. Son rôle est double :
Gérer le ubassrecorder pour le direct.
Charger des fichiers (WAV, MP3, M4A) via le Mixer BASS pour garantir que, peu importe la source, Whisper reçoive toujours du 16kHz Mono Float.
//

}

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
    Label7: TLabel;
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
    FCapturedText: TStringList;
    procedure WhisperFinished(Sender: Tobject);
    //
    procedure HandleRecorderLog(const Msg: string);
    procedure listdevices;
    procedure DisplayTranscription(const AText: string);
    procedure LogToMemo(const AMsg: string);
  public

  end;


var
  frmmain: Tfrmmain;
  WhisperEngine: TWhisperEngine;
  FAudioManager:TAudioCaptureManager;

  WAV_FILE :string= 'output.wav';
  MODEL_FILE:string = 'ggml-small.bin';
  start:int64;
  WhisperThread:tWhisperThread;
  WhisperLogBuffer: TStringList; // Le tampon de messages

implementation

{$R *.lfm}



{ Tfrmmain }

procedure Tfrmmain.LogToMemo(const AMsg: string);
begin

      Memo1.Lines.BeginUpdate;
      try
        Memo1.Lines.Add(AMsg);
      finally
        Memo1.Lines.EndUpdate;
      end;

      // Scroll automatique vers le bas
      SendMessage(Memo1.Handle, EM_SCROLLCARET, 0, 0);
end;

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
  // On récupère la liste via le manager
  DeviceList := FAudioManager.Recorder.GetLoopbackDevices;
  try
    cmbDevices.Items.Clear;
    for i := 0 to DeviceList.Count - 1 do
      cmbDevices.Items.AddObject(DeviceList[i], DeviceList.Objects[i]);

    if cmbDevices.Items.Count > 0 then
      cmbDevices.ItemIndex := 0;
  finally
    DeviceList.Free;
  end;
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




procedure Tfrmmain.WhisperFinished(Sender: Tobject);
var
  SaveDlg: TSaveDialog;
begin
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

      // 2. LOGIQUE DE SECOURS (Ton code original préservé)
      if (not WhisperThread.IsCancelled) and (not WhisperThread.FileWasOpened) then
      begin
        if (WhisperThread.FullTextResult <> nil) and (WhisperThread.FullTextResult.Count > 0) then
        begin
          if MessageDlg('Erreur d''écriture',
             'Le fichier SRT n''a pas pu être créé sur le disque.' + sLineBreak +
             'Voulez-vous enregistrer le résultat manuellement ?',
             mtWarning, [mbYes, mbNo], 0) = mrYes then
          begin
            SaveDlg := TSaveDialog.Create(nil);
            try
              SaveDlg.DefaultExt := 'srt';
              SaveDlg.Filter := 'Fichiers SRT|*.srt|Tous les fichiers|*.*';
              SaveDlg.InitialDir := ExtractFilePath(txtaudio.Text);
              if (SaveDlg.InitialDir = '') or not DirectoryExists(SaveDlg.InitialDir) then
                SaveDlg.InitialDir := GetCurrentDir;

              SaveDlg.FileName := ChangeFileExt(ExtractFileName(txtaudio.Text), '') +
                                  '_' + FormatDateTime('hhmmss', Now) + '.srt';
              if SaveDlg.Execute then
                WhisperThread.FullTextResult.SaveToFile(SaveDlg.FileName);
            finally
              SaveDlg.Free;
            end;
          end;
        end;
      end;

      // 3. LIBÉRATION SÉCURISÉE (C'est ici que ça change)
      // On met à jour l'UI d'abord
      btntranscribe.Caption := 'Transcribe';
      btntranscribe.Enabled := True;

      // Crucial : On demande au MOTEUR de s'arrêter.
      // Comme c'est lui qui a créé le thread, c'est lui qui doit faire le FreeAndNil.
      if Assigned(WhisperEngine) then
        WhisperEngine.Stop;

      // On vide notre variable locale car l'objet est maintenant détruit par le moteur
      WhisperThread := nil;
    end;
  finally
    // 4. SÉCURITÉ FINALE
    timer_transcribe.Enabled := False;
    ProgressBar1.Position := 0;
  end;
end;


procedure Tfrmmain.btntranscribeClick(Sender: TObject);
var
  Err: string;
begin
  // --- 1. LOGIQUE D'ARRÊT (Identique à ton code) ---
  if Assigned(WhisperThread) then
  begin
    btntranscribe.Enabled := False;
    Memo1.Lines.Add('Demande d''arrêt en cours...');
    WhisperThread.Terminate;
    Exit;
  end;

  Memo1.Lines.Clear;

  // --- 2. LECTURE WAV (Code déporté mais logs conservés) ---
  Memo1.Lines.Add('Lecture WAV…');
  if not FAudioManager.LoadWavFile3(txtaudio.Text, Err) then
  begin
    Memo1.Lines.Add(Err); // Affiche l'exception capturée ou le message d'erreur
    Exit;
  end;

  // Affichage du nombre d'échantillons comme avant
  Memo1.Lines.Add('Nombre d’échantillons : ' + IntToStr(FAudioManager.nFileSamples));

  memo1.Lines.Add ('Audio:'+txtaudio.Text);
  memo1.Lines.Add ('Langue:'+cmblang.Text);
  memo1.Lines.Add ('Preset:'+cmbpreset.Text);
  memo1.Lines.Add ('Threads:'+txtthreads.Text);

  // --- 3. TRANSCRIPTION ---
  WhisperEngine.StartTranscription(
    txtmodel.Text,
    @FAudioManager.FileSamples[0],
    FAudioManager.nFileSamples,
    cmbpreset.ItemIndex,
    cmblang.Text,
    txtthreads.Text,
    txtprompt.Text,
    'output.srt',
    chkgpu.Checked
  );

  // Récupération du thread pour le timer "pêcheur"
  WhisperThread := WhisperEngine.CurrentThread;

  if Assigned(WhisperThread) then
  begin
    btntranscribe.Caption := 'Stop';
    timer_transcribe.Enabled := True;
    start := GetTickCount64; // Pour le calcul de durée finale
    WhisperThread.Start;
  end;
end;

procedure Tfrmmain.btncaptureClick(Sender: TObject);
var
  SaveDlg: TSaveDialog;
  DeviceIdx: Integer;
begin
  if btnCapture.Caption = 'Capture' then
  begin
    // 1. Récupération de l'ID du périphérique sélectionné
    DeviceIdx := PtrInt(cmbDevices.Items.Objects[cmbDevices.ItemIndex]);

    // 2. On lance via le manager avec tous les paramètres de l'UI
    if FAudioManager.Start(
         DeviceIdx,
         txtmodel.Text,
         cmblang.Text,
         txtthreads.Text,
         txtPrompt.Text,
         cmbpreset.ItemIndex,
         chkgpu.Checked
       ) then
    begin
      btnCapture.Caption := 'Stop';
      Memo1.Lines.Add('🎤 Capture en cours via AudioManager...');

      // On vide le cumul précédent pour une nouvelle session propre
      FCapturedText.Clear;

      // On active le timer pour surveiller la fin des segments
      timer_capture.Enabled := True;
    end;
  end
  else
  begin
    // --- ARRÊT ---
    FAudioManager.Stop;

    btnCapture.Caption := 'Capture';
    timer_capture.Enabled := False;
    Memo1.Lines.Add('🛑 Capture arrêtée.');

    // --- TON CODE DE SAUVEGARDE ORIGINAL (Inchangé) ---
    if FCapturedText.Count > 0 then
    begin
      if MessageDlg('Capture terminée', 'Voulez-vous enregistrer le texte capturé en SRT ?',
         mtConfirmation, [mbYes, mbNo], 0) = mrYes then
      begin
        SaveDlg := TSaveDialog.Create(nil);
        try
          SaveDlg.DefaultExt := 'srt';
          SaveDlg.Filter := 'Fichiers SRT|*.srt|Tous les fichiers|*.*';
          SaveDlg.InitialDir := GetCurrentDir;
          SaveDlg.FileName := 'capture_' + FormatDateTime('hhmmss', Now) + '.srt';

          if SaveDlg.Execute then
            FCapturedText.SaveToFile(SaveDlg.FileName);
        finally
          SaveDlg.Free;
        end;
      end;
    end;
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
  OpenDialog1.Filter :='audio|*.wav;*.mp3;*.ogg;*.m4a;*.aac;*.mp2;';;
  OpenDialog1.Execute ;
  txtaudio.Text :=OpenDialog1.FileName ;
end;

procedure Tfrmmain.chklogChange(Sender: TObject);
begin

end;

procedure Tfrmmain.FormCreate(Sender: TObject);
begin
  // 1. Tes réglages de sécurité mathématique (indispensables pour les DLL audio/IA)
  SetExceptionMask([
    exInvalidOp,
    exDenormalized,
    exZeroDivide,
    exOverflow,
    exUnderflow,
    exPrecision
  ]);

  // 2. Valeurs par défaut de l'interface
    txtmodel.Text := 'ggml-small.bin';
    txtaudio.Text := 'output.wav';

    // 3. Initialisation du système de Logs
    WhisperLogBuffer := TStringList.Create;
    whisper_log_set(@MyWhisperLogCallback, nil);

    // 4. Initialisation des listes de données
    FCapturedText := TStringList.Create;

    // 5. CRÉATION DES MOTEURS (L'ordre est important)
    WhisperEngine := TWhisperEngine.Create;
    WhisperEngine.OnLog := @LogToMemo;

    // On passe WhisperEngine au constructeur du manager
    FAudioManager := TAudioCaptureManager.Create(WhisperEngine);

    // 6. Remplissage de la liste des périphériques
    // On peut encore utiliser le recorder interne du manager pour lister
    listdevices;

end;

procedure Tfrmmain.FormDestroy(Sender: TObject);
begin
  timer_transcribe.Enabled := False;
  timer_capture.Enabled := False;
  //
  whisper_log_set(nil, nil); // Désactive le callback
  if Assigned(WhisperLogBuffer) then FreeAndNil(WhisperLogBuffer);
  //
  FCapturedText.Free;

  // Libération des moteurs
  if Assigned(FAudioManager) then FreeAndNil(FAudioManager);

  if Assigned(WhisperEngine) then
  begin
    WhisperEngine.Stop;
    FreeAndNil(WhisperEngine);
  end;

end;



procedure Tfrmmain.timer_captureTimer(Sender: TObject);
var
  LThread: TWhisperThread;
  FinalText: string;
begin
  if [csDestroying, csLoading] * ComponentState <> [] then Exit;

  // On récupère le thread que le Manager a créé dans l'Engine
  WhisperThread := WhisperEngine.CurrentThread;

  LThread := WhisperThread;

  if Assigned(LThread) then
  begin
    // On met à jour la progressbar pendant que ça travaille
    ProgressBar1.Position := LThread.ProgressPercent;

    if LThread.Finished then
    begin
      // Avant de tuer le thread, on récupère le nombre de segments qu'il a généré
      // (Index final - Index de départ = nombre de nouveaux segments)
      WhisperEngine.AddSegments(LThread.FullTextResult.Count);
      //
      timer_capture.Enabled := False;
      try
        if Assigned(LThread.FullTextResult) and (LThread.FullTextResult.Count > 0) then
        begin
          FinalText := Trim(LThread.FullTextResult.Text);
          if FinalText <> '' then
          begin
            DisplayTranscription(FinalText);
            FCapturedText.Add(Format('[%s] %s', [FormatDateTime('HH:nn:ss', Now), FinalText]));
          end;
        end;
      finally
        if Assigned(WhisperEngine) then
          WhisperEngine.Stop;

        WhisperThread := nil;
        ProgressBar1.Position := 0;

        if btnCapture.Caption = 'Stop' then
          timer_capture.Enabled := True;
      end;
    end;
  end;
end;

procedure Tfrmmain.timer_transcribeTimer(Sender: TObject);
var
  LThread: TWhisperThread;
begin
  if [csDestroying, csLoading] * ComponentState <> [] then Exit;

  LThread := WhisperThread;
  if Assigned(LThread) then
  begin
    if LThread.Finished then
    begin
      // ON COUPE TOUT DE SUITE
      timer_transcribe.Enabled := False;
      WhisperFinished(LThread);
      Exit;
    end;

    try
      ProgressBar1.Position := LThread.ProgressPercent;
    except
      timer_transcribe.Enabled := False;
    end;
  end;

  // LOGS : On ajoute une sécurité pour ne pas bloquer l'UI
  if Assigned(WhisperLogBuffer) and (chklog.Checked) then
  begin
    if WhisperLogBuffer.Count > 0 then
    begin
      Memo1.Lines.BeginUpdate;
      try
        // On limite à 50 lignes par cycle pour laisser l'UI respirer
        while (WhisperLogBuffer.Count > 0) do
        begin
          Memo1.Lines.Add(WhisperLogBuffer[0]);
          WhisperLogBuffer.Delete(0);
          if Memo1.Lines.Count > 1000 then Memo1.Lines.Delete(0); // Evite l'explosion mémoire du Memo
        end;
      finally
        Memo1.Lines.EndUpdate;
        SendMessage(Memo1.Handle, EM_SCROLLCARET, 0, 0);
      end;
    end;
  end;
end;

end.

