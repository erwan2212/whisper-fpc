unit Ucapture;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ComCtrls, ubassrecorder,bass, basswasapi;

type

  { Tfrmmain }

  Tfrmmain = class(TForm)
    btnstart: TButton;
    btnstop: TButton;
    cmbdevices: TComboBox;
    lblstatus: TLabel;
    Memo1: TMemo;
    ProgressBar1: TProgressBar;
    procedure btnstartClick(Sender: TObject);
    procedure btnstopClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure Label1Click(Sender: TObject);
    procedure Label2Click(Sender: TObject);
  private
    FRecorder: TBassRecorder;
    procedure listdevices;
    procedure HandleRecorderLog(const Msg: string);
    procedure UpdateVuMeter(MaxAmp: Single);
    procedure CreateWavFile(const AFileName: string; ASampleRate: Cardinal);
    procedure OnAudioDataReceived(const Samples: array of Single);
  public

  end;

type
  // Structure standard d'un header WAV
  TWavHeader = packed record
    riff: array[0..3] of Char;      // 'RIFF'
    len: Cardinal;                 // Longueur totale - 8
    wave: array[0..3] of Char;      // 'WAVE'
    fmt: array[0..3] of Char;       // 'fmt '
    fmt_len: Cardinal;              // 16
    format: Word;                   // 3 (IEEE Float) ou 1 (PCM Integer)
    channels: Word;                 // 1
    sample_rate: Cardinal;          // 48000
    byte_rate: Cardinal;            // sample_rate * channels * 4
    block_align: Word;              // channels * 4
    bits_per_sample: Word;          // 32
    data_id: array[0..3] of Char;   // 'data'
    data_len: Cardinal;             // Longueur des données audio
  end;

var
  FFileStream: TFileStream;
  FWavHeader: TWavHeader;
  frmmain: Tfrmmain;

implementation

{$R *.lfm}

procedure Tfrmmain.OnAudioDataReceived(const Samples: array of Single);
var
  i: Integer;
  S: SmallInt;
begin
  if Assigned(FFileStream) then
  begin
    for i := 0 to High(Samples) do
    begin
      // Conversion Float vers 16 bits
      S := Round(Samples[i] * 32767);
      FFileStream.Write(S, 2);
      FWavHeader.data_len := FWavHeader.data_len + 2;
    end;
  end;
  Memo1.Lines.Add(Format('[%s] Reçu 1 seconde de son', [FormatDateTime('nn:ss.zzz', Now)]));
end;

procedure Tfrmmain.CreateWavFile(const AFileName: string; ASampleRate: Cardinal);
begin
  if Assigned(FFileStream) then FreeAndNil(FFileStream);

  FFileStream := TFileStream.Create(AFileName, fmCreate);

  FillChar(FWavHeader, SizeOf(TWavHeader), 0);
  FWavHeader.riff := 'RIFF';
  FWavHeader.wave := 'WAVE';
  FWavHeader.fmt := 'fmt ';
  FWavHeader.fmt_len := 16;
  FWavHeader.format := 3; // IEEE Float
  FWavHeader.channels := 1;

  // ON UTILISE LA FRÉQUENCE RÉELLE ICI
  FWavHeader.sample_rate := ASampleRate;

  FWavHeader.bits_per_sample := 32;
  FWavHeader.byte_rate := FWavHeader.sample_rate * FWavHeader.channels * 4;
  FWavHeader.block_align := FWavHeader.channels * 4;
  FWavHeader.data_id := 'data';
  FWavHeader.data_len := 0;
  FWavHeader.len := 36; // Header de base

  FFileStream.Write(FWavHeader, SizeOf(TWavHeader));
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
  // SUPPRIME CETTE LIGNE : FRecorder := TBassRecorder.Create;
  // Car FRecorder est déjà créé dans FormCreate !

  DeviceList := FRecorder.GetLoopbackDevices;
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

procedure Tfrmmain.FormCreate(Sender: TObject);
begin
  // On crée l'objet UNIQUE ici
  FRecorder := TBassRecorder.Create;
  // On branche l'événement UNIQUE ici
  FRecorder.OnAmplitude := @UpdateVuMeter;
  // On liste les périphériques en utilisant l'objet déjà créé
  ListDevices;
end;

procedure Tfrmmain.Label1Click(Sender: TObject);
begin

end;

procedure Tfrmmain.Label2Click(Sender: TObject);
begin

end;

procedure Tfrmmain.UpdateVuMeter(MaxAmp: Single);
begin
  // Si le beep est là, on force l'affichage ici
  if MaxAmp > 0.1 then
  begin
    lblStatus.Caption := 'AUDIO DETECTÉ !';
    // On force Windows à redessiner le label immédiatement
    lblStatus.Update;
  end;
end;

procedure Tfrmmain.btnstartClick(Sender: TObject);
var
  Idx: Integer;
begin
  Idx := PtrInt(cmbDevices.Items.Objects[cmbDevices.ItemIndex]);

  if FRecorder.StartCapture(Idx, 1.0) then
  begin
    FFileStream := TFileStream.Create('test_capture.wav', fmCreate);

    FillChar(FWavHeader, SizeOf(TWavHeader), 0);
    FWavHeader.riff := 'RIFF';
    FWavHeader.wave := 'WAVE';
    FWavHeader.fmt := 'fmt ';
    FWavHeader.fmt_len := 16;

    // --- CONFIGURATION PCM 16-BIT / 16KHZ ---
    FWavHeader.format := 1;          // PCM Standard
    FWavHeader.channels := 1;        // Mono
    FWavHeader.sample_rate := 16000; // 16kHz
    FWavHeader.bits_per_sample := 16;

    // Calculs automatiques basés sur les valeurs ci-dessus
    FWavHeader.byte_rate := FWavHeader.sample_rate * FWavHeader.channels * (FWavHeader.bits_per_sample div 8);
    FWavHeader.block_align := FWavHeader.channels * (FWavHeader.bits_per_sample div 8);

    FWavHeader.data_id := 'data';
    FWavHeader.data_len := 0;
    // La taille totale sera mise à jour au Stop

    FFileStream.Write(FWavHeader, SizeOf(TWavHeader));

    FRecorder.OnAudioChunk := @OnAudioDataReceived;
    Memo1.Lines.Add('✅ Enregistrement Standard PCM 16-bit 16kHz');
  end;
end;

procedure Tfrmmain.btnStopClick(Sender: TObject);
begin
  FRecorder.StopCapture;

  if Assigned(FFileStream) then
  begin
    // Mettre à jour les tailles dans le Header
    FWavHeader.len := FWavHeader.data_len + SizeOf(TWavHeader) - 8;
    FFileStream.Position := 0;
    FFileStream.Write(FWavHeader, SizeOf(TWavHeader));

    FreeAndNil(FFileStream);
    Memo1.Lines.Add('💾 Fichier test_capture.wav sauvegardé.');
  end;

  ProgressBar1.Position := 0;
end;

end.

