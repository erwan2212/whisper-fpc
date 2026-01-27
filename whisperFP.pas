program whisperFP;

{$mode objfpc}{$H+}

uses
  Math, classes,windows,SysUtils, whisper, sndfilefp;





var
  ctx: PWhisperContext;
  cparams: TWhisperContextParams;
  params: whisper_full_params;
  Samples: array of Single;
  nSamples: Integer;
  segData: TSegmentData;
  start:int64;
  SRTFile: Text;
  //
  WAV_FILE:string = 'output.wav';
  MODEL_FILE:string = 'ggml-small.bin';



  // ===== Lecture WAV mono 16kHz =====
procedure ReadWavMono16k(const Filename: string; out buffer: TArraySingle; out n: Integer);
var
  F: TFileStream;
  Header: array[0..43] of Byte;
  SampleCount, i: Integer;
  temp16: SmallInt;
begin
  F := TFileStream.Create(Filename, fmOpenRead or fmShareDenyNone);
  try
    F.ReadBuffer(Header, SizeOf(Header)); // Skip WAV header
    SampleCount := (F.Size - SizeOf(Header)) div 2;
    SetLength(buffer, SampleCount);
    for i := 0 to SampleCount - 1 do
    begin
      F.ReadBuffer(temp16, 2);
      buffer[i] := temp16 / 32768; // convert to float -1..1
    end;
  finally
    F.Free;
  end;
  n := SampleCount;
end;










begin
  SetExceptionMask([
    exInvalidOp,
    exDenormalized,
    exZeroDivide,
    exOverflow,
    exUnderflow,
    exPrecision
  ]);

  {
  WriteLn('Initialisation Whisper (GPU ou CPU)…');
  ctx := whisper_init_from_file(PChar(MODEL_FILE));
  if ctx = nil then
  begin
    WriteLn('Erreur: impossible de charger le modèle.');
    Halt(1);
  end;
  }

  if paramstr(1)<>'' then MODEL_FILE :=paramstr(1);
  if paramstr(2)<>'' then WAV_FILE :=paramstr(2);

  cparams := whisper_context_default_params;

    cparams.use_gpu := true;
    cparams.gpu_device := 0; // GPU 0
    cparams.flash_attn := True; // si supporté

    ctx := whisper_init_from_file_with_params(pchar(MODEL_FILE),cparams);
    if ctx = nil then
    begin
      WriteLn('Erreur: impossible de charger le modèle.');
      Halt(1);
    end;

 params:=preset_mid;

  params.language :='auto';
 if paramstr(3)<>'' then params.language :=pchar(paramstr(3));


 segData.LastEnd := 0.0;
 segData.SegmentIndex :=0;;

 {$i-}
 assignfile(segData.SRTFile ,WAV_FILE+'.srt');
 Rewrite(segData.SRTFile);
 {$i+}
 if IOResult <> 0 then Writeln('Erreur E/S : ', IOResult); // gestion de l’erreur : message, fallback, abort, etc.

    // Callback pour afficher segments + timestamps
    params.new_segment_callback := @SegmentCallback;
    // Offset initial = 0 ms
      params.new_segment_callback_user_data := @segData;

      // Initialiser offset pour le début de l'audio
      //segData.Offset := 0;

      //params.progress_callback := @ProgressCallback;
      //params.progress_callback_user_data := nil;


  // Lecture WAV
  WriteLn('Lecture WAV with libsndfile…');
  try
    ReadWavMono16kv2(WAV_FILE, Samples, nSamples);
  except
    on e:exception do
       begin
         writeln(e.Message );
         exit;
       end;
  end;
  WriteLn('Nombre d’échantillons : ', nSamples);
  if nSamples > 0 then WriteLn('Premier échantillon : ', Samples[0]:0:6);



  // Transcription
  WriteLn('Début transcription…');
  start:=gettickcount64;
  if whisper_full(ctx, params, @Samples[0], nSamples) <> 0 then
  WriteLn('Erreur lors de la transcription.');

  WriteLn('Terminé.');
  writeln('Total: ', (GetTickCount64 - start) / 1000:0:3, ' s');

  {
  writeln(segData.SegmentIndex);
  for start := 0 to segData.SegmentIndex - 1 do
begin
  WriteLn(Format(
    'Segment [%d] (%s --> %s): %s',
    [ start,
      SecondsToSRTFormat(whisper_full_get_segment_t0(ctx, start) *0.01),
      SecondsToSRTFormat(whisper_full_get_segment_t1(ctx, start) *0.01),
      whisper_full_get_segment_text(ctx, start)
    ]));
end;
}

  // Libération
  whisper_free(ctx);

  //
  {$i-}closefile(segData.SRTFile );{$i+}

end.


