unit whisper_api;

{$mode objfpc}{$H+}
{$PACKRECORDS 8} // Alignement C++ Win64

interface

type
  PWhisperContext = Pointer;
  PWhisperState = Pointer;

  // --- Callbacks C ---
  whisper_new_segment_callback = procedure(ctx: PWhisperContext; state: PWhisperState; n_new: Integer; user_data: Pointer); cdecl;
  whisper_progress_callback = function(ctx: PWhisperContext; state: PWhisperState; progress: Integer; user_data: Pointer): Byte; cdecl;
  whisper_encoder_begin_callback = procedure(ctx: PWhisperContext; user_data: Pointer); cdecl;
  ggml_abort_callback = function(user_data: Pointer): Byte; cdecl;
  whisper_logits_filter_callback = procedure(logits: PSingle; n_logits: Integer; user_data: Pointer); cdecl;
  whisper_log_callback = procedure(level: Integer; const text: PChar; user_data: Pointer); cdecl;

  // --- Structures de données ---
  whisper_full_params = record
    strategy: Integer;
    n_threads: Integer;
    n_max_text_ctx: Integer;
    offset_ms: Integer;
    duration_ms: Integer;
    translate, no_context, no_timestamps, single_segment, print_special,
    print_progress, print_realtime, print_timestamps, token_timestamps: Byte;
    thold_pt, thold_ptsum: Single;
    max_len: Integer;
    split_on_word: Byte;
    max_tokens: Integer;
    debug_mode: Byte;
    audio_ctx: Integer;
    tdrz_enable: Byte;
    suppress_regex, initial_prompt: PChar;
    carry_initial_prompt: Byte;
    prompt_tokens: Pointer;
    prompt_n_tokens: Integer;
    language: PChar;
    detect_language, suppress_blank, suppress_nst: Byte;
    temperature, max_initial_ts, length_penalty, temperature_inc,
    entropy_thold, logprob_thold, no_speech_thold: Single;
    greedy_best_of, beam_search_beam_size: Integer;
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
    vad_params: Pointer;
  end;

  TWhisperContextParams = packed record
    use_gpu, flash_attn: Boolean;
    _pad1: Word;
    gpu_device: Integer;
    dtw_token_timestamps: Boolean;
    _pad2: array[0..2] of Byte;
    dtw_aheads_preset: Integer;
    dtw_n_top: Integer;
    n_heads: Integer;
    heads: Pointer;
    dtw_mem_size: SizeUInt;
  end;

// --- Imports DLL ---
const WHISPER_DLL = 'whisper.dll';

function whisper_init_from_file_with_params(path_model: PChar; params: TWhisperContextParams): PWhisperContext; cdecl; external WHISPER_DLL;
procedure whisper_free(ctx: PWhisperContext); cdecl; external WHISPER_DLL;
function whisper_full(ctx: PWhisperContext; const params: whisper_full_params; samples: PSingle; n_samples: Integer): Integer; cdecl; external WHISPER_DLL;
function whisper_full_n_segments(ctx: PWhisperContext): Integer; cdecl; external WHISPER_DLL;
function whisper_full_get_segment_text(ctx: PWhisperContext; i: Integer): PChar; cdecl; external WHISPER_DLL;
function whisper_full_get_segment_t0(ctx: PWhisperContext; i: Integer): Int64; cdecl; external WHISPER_DLL;
function whisper_full_get_segment_t1(ctx: PWhisperContext; i: Integer): Int64; cdecl; external WHISPER_DLL;
procedure whisper_log_set(cb: whisper_log_callback; user_data: Pointer); cdecl; external WHISPER_DLL;
function whisper_context_default_params: TWhisperContextParams; cdecl; external WHISPER_DLL;

implementation
end.
