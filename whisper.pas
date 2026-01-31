unit whisper;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, whisper_api; // Utilise l'unité de binding

type
  PSegmentData = ^TSegmentData;
  TSegmentData = record
    SRTFile: Text;
    SegmentIndex: Integer;
    LastEnd: Single;
    FileOpened: Boolean;
    FullText: TStringList;
  end;

// On garde TES noms de fonctions originaux pour ne rien casser
function SecondsToSRTFormat(sec: Single): string;
procedure SegmentCallback(ctx: PWhisperContext; state: PWhisperState; n_new: Integer; user_data: Pointer); cdecl;

function preset_def: whisper_full_params;
function preset_perf: whisper_full_params;
function preset_mid: whisper_full_params;
function preset_qual: whisper_full_params;

implementation

function SecondsToSRTFormat(sec: Single): string;
var
  h, m, s, ms: Integer;
begin
  h := Trunc(sec / 3600);
  m := Trunc((sec - h*3600) / 60);
  s := Trunc(sec - h*3600 - m*60);
  ms := Trunc(Frac(sec) * 1000);
  Result := Format('%.2d:%.2d:%.2d,%.3d', [h, m, s, ms]);
end;

procedure SegmentCallback(ctx: PWhisperContext; state: PWhisperState; n_new: Integer; user_data: Pointer); cdecl;
var
  i, nSeg, s0: Integer;
  t0_10ms, t1_10ms: Int64;
  t0_sec, t1_sec: Double;
  text: PChar;
  srtline: string;
begin
  if (n_new <= 0) or (user_data = nil) then Exit;

  nSeg := whisper_full_n_segments(ctx);
  if nSeg = 0 then Exit;

  s0 := nSeg - n_new;
  if s0 < 0 then s0 := 0;

  for i := s0 to nSeg - 1 do
  begin
    t0_10ms := whisper_full_get_segment_t0(ctx, i);
    t1_10ms := whisper_full_get_segment_t1(ctx, i);

    t0_sec := t0_10ms * 0.01;
    t1_sec := t1_10ms * 0.01;

    text := whisper_full_get_segment_text(ctx, i);

    //srtline := Format('[%d] %s --> %s: %s', [i, SecondsToSRTFormat(t0_sec), SecondsToSRTFormat(t1_sec), text]);
    srtline := Format('[%d] %s --> %s: %s', [PSegmentData(user_data)^.SegmentIndex, SecondsToSRTFormat(t0_sec), SecondsToSRTFormat(t1_sec), text]);

    if Assigned(PSegmentData(user_data)^.FullText) then
      PSegmentData(user_data)^.FullText.Add(SrtLine);

    if PSegmentData(user_data)^.FileOpened then
    begin
      {$i-}WriteLn(PSegmentData(user_data)^.SRTFile, SrtLine);{$i-}
      if IOResult <> 0 then PSegmentData(user_data)^.FileOpened := False;
    end;
    Inc(PSegmentData(user_data)^.SegmentIndex);
  end;
end;

function preset_qual: whisper_full_params;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.strategy := 1; // WHISPER_SAMPLING_BEAM_SEARCH
  Result.beam_search_beam_size := 5;
  Result.greedy_best_of := 5;
  Result.beam_search_patience := -1.0;
  Result.temperature := 0.0;
  Result.temperature_inc := 0.2;
  Result.n_max_text_ctx := 448;
  Result.no_speech_thold := 0.6;
  Result.logprob_thold := -1.0;
  Result.entropy_thold := 2.4;
  Result.n_threads := 4;
end;

function preset_mid: whisper_full_params;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.strategy := 1; // WHISPER_SAMPLING_BEAM_SEARCH
  Result.beam_search_beam_size := 3;
  Result.beam_search_patience := -1.0;
  Result.temperature := 0.0;
  Result.temperature_inc := 0.2;
  Result.n_max_text_ctx := 100;
  Result.no_speech_thold := 0.6;
  Result.logprob_thold := -1.0;
  Result.entropy_thold := 2.4;
  Result.n_threads := 4;
end;

function preset_perf: whisper_full_params;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.strategy := 0; // WHISPER_SAMPLING_GREEDY
  Result.temperature := 0.0;
  Result.temperature_inc := 0.0;
  Result.n_max_text_ctx := 50;
  Result.no_speech_thold := 0.6;
  Result.logprob_thold := -1.0;
  Result.entropy_thold := 2.4;
  Result.n_threads := 4;
end;

function preset_def: whisper_full_params;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.strategy := 0; // WHISPER_SAMPLING_GREEDY
  Result.n_threads := 4;
end;

end.
