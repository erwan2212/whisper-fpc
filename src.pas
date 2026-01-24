const
  SRC_SINC_BEST_QUALITY   = 0;
  SRC_SINC_MEDIUM_QUALITY = 1;
  SRC_SINC_FASTEST        = 2;

type
  PSRC_DATA = ^SRC_DATA;
  SRC_DATA = record
    data_in: PSingle;
    data_out: PSingle;
    input_frames: LongInt;
    output_frames: LongInt;
    src_ratio: Double;
  end;

function src_simple(data: PSRC_DATA; converter_type: Integer; channels: Integer): Integer;
  cdecl; external 'samplerate.dll';
  
procedure ResampleTo16k(
  const InBuf: TArraySingle;
  InRate: Integer;
  out OutBuf: TArraySingle
);
var
  src: SRC_DATA;
  ratio: Double;
  outFrames: Integer;
begin
  if InRate = 16000 then
  begin
    OutBuf := Copy(InBuf);
    Exit;
  end;

  ratio := 16000 / InRate;
  outFrames := Round(Length(InBuf) * ratio);

  SetLength(OutBuf, outFrames);

  src.data_in := @InBuf[0];
  src.data_out := @OutBuf[0];
  src.input_frames := Length(InBuf);
  src.output_frames := outFrames;
  src.src_ratio := ratio;

  if src_simple(@src, SRC_SINC_MEDIUM_QUALITY, 1) <> 0 then
    raise Exception.Create('Resampling failed');
end;


procedure StereoToMono(
  const InBuf: TArraySingle;
  Channels: Integer;
  out Mono: TArraySingle
);
var
  i, f: Integer;
begin
  SetLength(Mono, Length(InBuf) div Channels);
  f := 0;
  for i := 0 to High(Mono) do
  begin
    Mono[i] := 0;
    for f := 0 to Channels - 1 do
      Mono[i] += InBuf[i*Channels + f];
    Mono[i] /= Channels;
  end;
end;

