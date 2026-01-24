unit sndfilefp;

{$mode objfpc}{$H+}

interface

uses sysutils;

type
  TSF_COUNT_T = Int64;
  PSNDFILE = Pointer;

  TSF_INFO = record
    frames     : TSF_COUNT_T;
    samplerate : Integer;
    channels   : Integer;
    format     : Integer;
    sections   : Integer;
    seekable   : Integer;
  end;
  PSF_INFO = ^TSF_INFO;

  TArraySingle = array of Single;

const
  SFM_READ = $10;

function sf_open(path: PChar; mode: Integer; sfinfo: PSF_INFO): PSNDFILE; cdecl; external 'libsndfile-1.dll';
function sf_readf_float(sndfile: PSNDFILE; ptr: PSingle; frames: TSF_COUNT_T): TSF_COUNT_T; cdecl; external 'libsndfile-1.dll';
function sf_close(sndfile: PSNDFILE): Integer; cdecl; external 'libsndfile-1.dll';

procedure ReadWavMono16kv2(const Filename: string; out buffer: TArraySingle; out n: Integer);

implementation

//Format Support : WAV (PCM 8/16/24/32 bits), WAV float, AIFF / AIFC, FLAC, OGG Vorbis, AU / RAW, CAF
//Sample rate	Support : 8 kHz, 16 kHz, 44.1 kHz, 48 kHz, Autres
//not supported : MP3, M4A / AAC, OPUS, WMA -> ffmpeg -i input.mp3 -ar 16000 -ac 1 -f wav pipe:

{
Logique :

extension supportée ?

sample rate ≠ 16k → ffmpeg

stéréo → downmix

format compressé → ffmpeg

sinon → libsndfile direct
}

{
Recommandation finale (pour ton projet)

libsndfile → lecture rapide
libsamplerate → resampling propre
Whisper → transcription
ffmpeg uniquement si format compressé
}

function IsSupportedBySndfile(const Ext: string): Boolean;
begin
  case LowerCase(Ext) of
    '.wav', '.flac', '.ogg', '.aiff', '.aif': Result := True;
    else Result := False;
  end;
end;

procedure ReadWavMono16kv2(const Filename: string; out buffer: TArraySingle; out n: Integer);
var
  sf       : PSNDFILE;
  info     : TSF_INFO;
  tmp      : TArraySingle;
  i, f     : Integer;
begin
  FillChar(info, SizeOf(info), 0);

  sf := sf_open(PChar(Filename), SFM_READ, @info);
  if sf = nil then
    raise Exception.Create('Impossible d’ouvrir le fichier audio');

  try
    if info.samplerate <> 16000 then
      raise Exception.CreateFmt('Samplerate invalide (%d Hz), 16 kHz requis', [info.samplerate]);

    // Allocation : frames * channels
    SetLength(tmp, info.frames * info.channels);

    // Lecture C ultra rapide
    f := sf_readf_float(sf, @tmp[0], info.frames);
    if f <> info.frames then
      raise Exception.Create('Lecture audio incomplète');

    // Conversion mono si nécessaire
    if info.channels = 1 then
    begin
      buffer := tmp;
      n := info.frames;
    end
    else
    begin
      SetLength(buffer, info.frames);
      for i := 0 to info.frames - 1 do
        buffer[i] := tmp[i * info.channels]; // canal gauche
      n := info.frames;
    end;

  finally
    sf_close(sf);
  end;
end;

end.

