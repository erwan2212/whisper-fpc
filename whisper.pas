unit whisper;

{$mode objfpc}{$H+}
{$PACKRECORDS 8} // Aligne les records comme le compilateur C++ (Win64)

interface

uses
  SysUtils;

type
  PWhisperContext = Pointer;
  PWhisperState = Pointer; // opaque

  // Callback types
  whisper_new_segment_callback         = procedure (ctx: PWhisperContext;state: PWhisperState;n_new: Integer;user_data: Pointer); cdecl;
  whisper_progress_callback = function(ctx: PWhisperContext; state: PWhisperState; progress: Integer; user_data: Pointer): Byte; cdecl;
  whisper_encoder_begin_callback     = procedure(ctx: PWhisperContext; user_data: Pointer); cdecl;
  ggml_abort_callback                = function(user_data: Pointer): Byte; cdecl;
  whisper_logits_filter_callback     = procedure(logits: PSingle; n_logits: Integer; user_data: Pointer); cdecl;

  // Full params struct corrected
  whisper_full_params = {packed} record
    strategy: Integer;
    n_threads: Integer;
    n_max_text_ctx: Integer;
    offset_ms: Integer;
    duration_ms: Integer;

    translate: Byte;
    no_context: Byte;
    no_timestamps: Byte;
    single_segment: Byte;
    print_special: Byte;
    print_progress: Byte;
    print_realtime: Byte;
    print_timestamps: Byte;

    token_timestamps: Byte;
    thold_pt: Single;
    thold_ptsum: Single;
    max_len: Integer;
    split_on_word: Byte;
    max_tokens: Integer;

    debug_mode: Byte;
    audio_ctx: Integer;

    tdrz_enable: Byte;

    suppress_regex: PChar;
    initial_prompt: PChar;
    carry_initial_prompt: Byte;
    prompt_tokens: Pointer;
    prompt_n_tokens: Integer;

    language: PChar;
    detect_language: Byte;

    suppress_blank: Byte;
    suppress_nst: Byte;

    temperature: Single;
    max_initial_ts: Single;
    length_penalty: Single;
    temperature_inc: Single;
    entropy_thold: Single;
    logprob_thold: Single;
    no_speech_thold: Single;

    greedy_best_of: Integer;
    beam_search_beam_size: Integer;
    beam_search_patience: Single;

    new_segment_callback: whisper_new_segment_callback;
    new_segment_callback_user_data: Pointer;

    progress_callback: whisper_progress_callback;
    progress_callback_user_data: Pointer;

    encoder_begin_callback: whisper_encoder_begin_callback;
    encoder_begin_callback_user_data: Pointer;

    abort_callback: ggml_abort_callback;
    abort_callback_user_data: Pointer;

    logits_filter_callback: whisper_logits_filter_callback;
    logits_filter_callback_user_data: Pointer;

    grammar_rules: Pointer;
    n_grammar_rules: NativeUInt;
    i_start_rule: NativeUInt;
    grammar_penalty: Single;

    vad: Byte;
    vad_model_path: PChar;
    vad_params: Pointer; // whisper_vad_params*
  end;

type
  // équivalent enum whisper_alignment_heads_preset
  whisper_alignment_heads_preset = Integer;

  // struct whisper_aheads (opaque ici si tu ne l’utilises pas)
  whisper_aheads = record
    n_heads: Integer;
    heads: Pointer;
  end;

  PWhisperContextParams = ^TWhisperContextParams;
  TWhisperContextParams = packed record
    use_gpu: Boolean;               // bool (1 byte)
    flash_attn: Boolean;            // bool (1 byte)
    _pad1: Word;                    // padding → align int

    gpu_device: Integer;            // int

    dtw_token_timestamps: Boolean;  // bool
    _pad2: array[0..2] of Byte;     // padding → align enum

    dtw_aheads_preset: whisper_alignment_heads_preset; // enum = int

    dtw_n_top: Integer;

    dtw_aheads: whisper_aheads;

    dtw_mem_size: SizeUInt;         // size_t
  end;


    PSegmentData = ^TSegmentData;
  TSegmentData = record
    //Offset: Single; // offset cumulé depuis le début de l'audio
    SRTFile: Text;         // fichier SRT ouvert
    SegmentIndex: Integer; // compteur de segments
    LastEnd: Single;
  end;

  whisper_log_callback = procedure(level: Integer; const text: PChar; user_data: Pointer); cdecl;

  // Sampling strategies
  whisper_sampling_strategy = (WHISPER_SAMPLING_GREEDY = 0,WHISPER_SAMPLING_BEAM_SEARCH=1);



function whisper_init_from_file(path_model: PChar): PWhisperContext; cdecl; external 'whisper.dll';
procedure whisper_free(ctx: PWhisperContext); cdecl; external 'whisper.dll';
//function whisper_full_default_params(strategy: Integer): whisper_full_params; cdecl; external 'whisper.dll'; //instable
function whisper_full(ctx: PWhisperContext; const params: whisper_full_params; samples: PSingle; n_samples: Integer): Integer; cdecl; external 'whisper.dll';
function whisper_full_n_segments(ctx: PWhisperContext): Integer; cdecl; external 'whisper.dll';
function whisper_full_get_segment_text(ctx: PWhisperContext; i: Integer): PChar; cdecl; external 'whisper.dll';
function whisper_full_get_segment_t0(ctx: PWhisperContext; i: Integer): Int64; cdecl; external 'whisper.dll';
function whisper_full_get_segment_t1(ctx: PWhisperContext; i: Integer): Int64; cdecl; external 'whisper.dll';
procedure whisper_log_set(cb: whisper_log_callback; user_data: Pointer); cdecl; external 'whisper.dll';

function whisper_context_default_params: TWhisperContextParams; cdecl; external 'whisper.dll';

function whisper_init_from_file_with_params(path_model: PChar;params: TWhisperContextParams): PWhisperContext; cdecl;  external 'whisper.dll';

//

procedure SegmentCallback(ctx: PWhisperContext;state: PWhisperState;n_new: Integer;user_data: Pointer); cdecl;


function preset_def:whisper_full_params;
function preset_perf:whisper_full_params;
function preset_mid:whisper_full_params;
function preset_qual:whisper_full_params;

implementation

// ------------------------------------------
// Helper : convertit secondes en "HH:MM:SS,mmm"
// ------------------------------------------
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

// --- CALLBACK POUR LES SEGMENTS ---
//procedure SegmentCallback(ctx: PWhisperContext; user_data: Pointer); cdecl;
procedure SegmentCallback(ctx: PWhisperContext;state: PWhisperState;n_new: Integer;user_data: Pointer); cdecl;
var
  i, nSeg, s0: Integer;
  t0_10ms, t1_10ms: Int64;
  t0_sec, t1_sec: Double;
  text: PChar;
begin
  //windows.MessageBoxA (0,'callback','whisper',0);
  if n_new <= 0 then Exit;

  nSeg := whisper_full_n_segments(ctx);
  if nSeg = 0 then Exit;

  //i := nSeg - 1; //sans gestion de n_new

  // Premier index des nouveaux segments
  s0 := nSeg - n_new;
  if s0 < 0 then s0 := 0;

  for i := s0 to nSeg - 1 do
  begin

  t0_10ms := whisper_full_get_segment_t0(ctx, i);
  t1_10ms := whisper_full_get_segment_t1(ctx, i);

  t0_sec := t0_10ms * 0.01;
  t1_sec := t1_10ms * 0.01;

  text := whisper_full_get_segment_text(ctx, i);

  if IsConsole then
  WriteLn(Format(
    'Segment [%d] (%s --> %s): %s',
    [ i,
      SecondsToSRTFormat(t0_sec),
      SecondsToSRTFormat(t1_sec),
      text
    ]));

  {$i-}
  if TTextRec(PSegmentData(user_data)^.SRTFile).Mode <>0 then
    WriteLn(PSegmentData(user_data)^.SRTFile , Format(
    '[%d] %s --> %s: %s',
    [ i,
      SecondsToSRTFormat(t0_sec),
      SecondsToSRTFormat(t1_sec),
      text
    ]));
  {$i+}
  end;

  inc(PSegmentData(user_data)^.SegmentIndex); //dans le for ou pas?

end;

//avec clamping : pas satisfaisant...
procedure SegmentCallback1(ctx: PWhisperContext; user_data: Pointer); cdecl;
var
  nSeg, i: Integer;
  t0, t1: Single;
  t0_abs, t1_abs: Single;
  segData: PSegmentData;
  text: PChar;
begin
  if user_data = nil then Exit;
  segData := PSegmentData(user_data);

  nSeg := whisper_full_n_segments(ctx);
  if nSeg = 0 then Exit;

  i := nSeg - 1;

  t0 := whisper_full_get_segment_t0(ctx, i);
  t1 := whisper_full_get_segment_t1(ctx, i);
  text := whisper_full_get_segment_text(ctx, i);

  t0_abs := t0;
  t1_abs := t1;

  // --- clamp temporel ---
  if t0_abs < segData^.LastEnd then
    t0_abs := segData^.LastEnd;

  if t1_abs < t0_abs then
    t1_abs := t0_abs;

  WriteLn(Format(
    'Segment [%d] (%s --> %s): %s',
    [i, SecondsToSRTFormat(t0_abs), SecondsToSRTFormat(t1_abs), text]
  ));

  segData^.LastEnd := t1_abs;
end;

function preset_qual:whisper_full_params;
begin

  {
  Avantages
  Texte le plus fidèle
  Moins de mots manquants
  Segments très stables dans le temps
  Inconcnt (×2 à ×3 par rapport greedy)
  Consommation CPU élevée
  }

  // 1. On remplit TOUT de zéros d'abord (très important pour les pointeurs non utilisés)
  //result := whisper_full_default_params(longint(WHISPER_SAMPLING_BEAM_SEARCH)); //
  FillChar(Result, SizeOf(Result), 0);

  // 2. On initialise manuellement les valeurs par défaut standards de Whisper
    result.strategy := longint(WHISPER_SAMPLING_BEAM_SEARCH);
    result.beam_search_beam_size := 5;
    result.greedy_best_of := 5; //(même en Beam Search, cela aide pour les décisions de fallback).
    result.beam_search_patience := -1.0; //(valeur par défaut pour "auto"). Si c'est à 0.0 (via FillChar), le Beam Search pourrait s'arrêter trop tôt.

    result.temperature := 0.0;
    result.temperature_inc := 0.2;

    result.n_max_text_ctx := 448; //max

    result.no_speech_thold := 0.6;
    result.logprob_thold := -1.0;
    result.entropy_thold := 2.4;

    result.no_timestamps := 0;
    result.token_timestamps := 0;

   result.n_threads :=4;

end;

function preset_mid:whisper_full_params;
begin
  {
  Avantages
  Très proche de whisper-cli
  Timestamps cohérents
  Texte fiable
  Temps de calcul maîtrisé
  }

  // 1. On remplit TOUT de zéros d'abord (très important pour les pointeurs non utilisés)
  //result := whisper_full_default_params(longint(WHISPER_SAMPLING_BEAM_SEARCH)); //
  FillChar(Result, SizeOf(Result), 0);

  // 2. On initialise manuellement les valeurs par défaut standards de Whisper
  result.strategy := longint(WHISPER_SAMPLING_BEAM_SEARCH);
  result.beam_search_beam_size := 3;

  result.temperature := 0.0;
  result.temperature_inc := 0.2;

  result.n_max_text_ctx := 100; //def 50

  result.no_speech_thold := 0.6;
  result.logprob_thold := -1.0;
  result.entropy_thold := 2.4;

  result.no_timestamps := 0;
  result.token_timestamps := 0;

  result.n_threads :=4;

  //Result.print_progress := 1;
  //Result.print_timestamps := 1;
end;

function preset_perf:whisper_full_params;
begin
  {
  Avantages
  Très rapide
  CPU minimal
  Idéal pour gros volumes
  Inconvénients
  Erreurs plus fréquentes
  Segments parfois moins naturels
  Moins bon pour voix rapides / bruit
  }

  // 1. On remplit TOUT de zéros d'abord (très important pour les pointeurs non utilisés)
  //result := whisper_full_default_params(longint(WHISPER_SAMPLING_GREEDY)); //
  FillChar(Result, SizeOf(Result), 0);

  // 2. On initialise manuellement les valeurs par défaut standards de Whisper
  result.strategy := longint(WHISPER_SAMPLING_GREEDY);
  result.temperature := 0.0;
  result.temperature_inc := 0.0;

  result.n_max_text_ctx := 0; //radical. Cela signifie que Whisper n'a aucune mémoire de ce qu'il a dit juste avant. C'est très rapide, mais la grammaire peut en souffrir.

  result.no_speech_thold := 0.6;
  result.logprob_thold := -1.0;
  result.entropy_thold := 2.4;

  result.no_timestamps := 0;
  result.token_timestamps := 0;

  result.n_threads :=4;

  //result.suppress_blank := 1; //. Cela évite que le modèle ne boucle sur du silence au début ou à la fin.

end;

function preset_def:whisper_full_params;
begin
  // 1. On remplit TOUT de zéros d'abord (très important pour les pointeurs non utilisés)
  //result := whisper_full_default_params(longint(WHISPER_SAMPLING_GREEDY)); //
  FillChar(Result, SizeOf(Result), 0);

  // 2. On initialise manuellement les valeurs par défaut standards de Whisper
  result.strategy := longint(WHISPER_SAMPLING_GREEDY);
  result.no_timestamps := 0;
  //params.print_timestamps := 1;        // si tu veux un log de timestamp ??
  result.token_timestamps := 0;        // niveau segment Un segment = une phrase / portion cohérente
                                  // vs Niveau token (mot / sous-mot) Chaque mot (en réalité : token BPE) peut aussi recevoir un timestamp
  result.offset_ms := 0;               // commence au début du wav
  result.duration_ms := 0;             // traiter tout le fichier



end;

//SetEnvironmentVariable('VK_ICD_FILENAMES', '');
//SetEnvironmentVariable('GGML_VULKAN', '0')

end.

