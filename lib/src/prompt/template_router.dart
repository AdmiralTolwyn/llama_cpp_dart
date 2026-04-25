import 'dart:ffi';
import 'package:ffi/ffi.dart';
import '../core/llama_cpp.dart';
import 'prompt_format.dart';
import 'chatml_format.dart';
import 'gemma_format.dart';
import 'alpaca_format.dart';
import 'harmony_format.dart';

/// Detects the correct [PromptFormat] for a model from its architecture/family.
///
/// Uses llama.cpp's embedded model description and metadata for reliable routing,
/// falling back to filename keyword matching. Eliminates guesswork in template
/// selection for Gemma, Phi, Llama, Qwen, and SmolLM families.
///
/// Usage:
/// ```dart
/// final format = TemplateRouter.detectFormat(model: llamaModelPtr);
/// final parent = LlamaParent(loadCmd, format);
/// ```
class TemplateRouter {
  /// Detects the best [PromptFormat] for the loaded model.
  ///
  /// Pass [model] (a loaded `Pointer<llama_model>`) and optionally the
  /// [filename] for fallback keyword matching when metadata is absent.
  static PromptFormat detectFormat({
    required Pointer<llama_model> model,
    required llama_cpp lib,
    String? filename,
  }) {
    final arch = _readModelArch(model, lib);
    final desc = _readModelDesc(model, lib);

    // Combine arch + desc + filename for matching
    final combined =
        '${arch.toLowerCase()} ${desc.toLowerCase()} ${(filename ?? '').toLowerCase()}';

    return _routeFromString(combined);
  }

  /// Convenience overload — detect purely from a filename/path string.
  /// Use when model is not yet loaded (e.g. for UI display before download).
  static PromptFormat detectFromFilename(String filename) {
    return _routeFromString(filename.toLowerCase());
  }

  // ── Internal routing ────────────────────────────────────────────────────────

  static PromptFormat _routeFromString(String s) {
    // Gemma family (Google) — uses <start_of_turn> / <end_of_turn>
    // Covers: gemma-2, gemma-3, gemma-3n, gemma-4, gemma4
    if (_matches(s, ['gemma'])) {
      return GemmaFormat();
    }

    // Phi family (Microsoft) — uses <|system|> / <|user|> / <|assistant|> / <|end|>
    // Covers: phi-2, phi-3, phi-4, phi4-mini, phi-4-mini
    if (_matches(s, ['phi'])) {
      return HarmonyFormat();
    }

    // SmolLM / SmolLM3 / SmolVLM (HuggingFace) — uses ChatML
    if (_matches(s, ['smollm', 'smol_lm'])) {
      return ChatMLFormat();
    }

    // Qwen family (Alibaba) — uses ChatML (<|im_start|> / <|im_end|>)
    // Covers: qwen2, qwen2.5, qwen3, qwen3.5, qwq
    if (_matches(s, ['qwen', 'qwq'])) {
      return ChatMLFormat();
    }

    // Yi family (01-AI) — uses ChatML
    if (_matches(s, ['yi-'])) {
      return ChatMLFormat();
    }

    // Mistral / Mixtral — uses ChatML-like format
    if (_matches(s, ['mistral', 'mixtral', 'nemo'])) {
      return ChatMLFormat();
    }

    // DeepSeek — uses ChatML
    if (_matches(s, ['deepseek'])) {
      return ChatMLFormat();
    }

    // Llama 3 / Llama 3.1 / Llama 3.2 / Llama 4 (Meta)
    // Uses <|begin_of_text|> ... <|eot_id|> format — closest is HarmonyFormat
    // (Phi-style tokens; Llama3 has <|start_header_id|>role<|end_header_id|>)
    if (_matches(s, ['llama-3', 'llama3', 'llama 3'])) {
      return _Llama3Format();
    }

    // Llama 2 / older Llama — uses [INST] format → AlpacaFormat is closest
    if (_matches(s, ['llama-2', 'llama2', 'llama 2'])) {
      return AlpacaFormat();
    }

    // Alpaca / instruction-tuned generic
    if (_matches(s, ['alpaca', 'instruct'])) {
      return AlpacaFormat();
    }

    // Default fallback — ChatML is the most widely supported modern format
    return ChatMLFormat();
  }

  static bool _matches(String haystack, List<String> needles) {
    return needles.any((n) => haystack.contains(n));
  }

  static String _readModelArch(Pointer<llama_model> model, llama_cpp lib) {
    try {
      // llama_model_desc returns "llama 3.2 3B Q4_K_M" style strings
      final buf = calloc<Char>(256);
      lib.llama_model_desc(model, buf, 256);
      final result = buf.cast<Utf8>().toDartString();
      calloc.free(buf);
      return result;
    } catch (_) {
      return '';
    }
  }

  static String _readModelDesc(Pointer<llama_model> model, llama_cpp lib) {
    // Also try to read the "general.architecture" metadata key
    try {
      final keyBuf = 'general.architecture'.toNativeUtf8().cast<Char>();
      final valBuf = calloc<Char>(128);
      final ret = lib.llama_model_meta_val_str(model, keyBuf, valBuf, 128);
      malloc.free(keyBuf);
      if (ret > 0) {
        final arch = valBuf.cast<Utf8>().toDartString();
        calloc.free(valBuf);
        return arch;
      }
      calloc.free(valBuf);
    } catch (_) {}
    return '';
  }
}

// ── Llama 3 format ─────────────────────────────────────────────────────────
// <|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n{content}<|eot_id|>
// <|start_header_id|>user<|end_header_id|>\n\n{content}<|eot_id|>
// <|start_header_id|>assistant<|end_header_id|>\n\n

class _Llama3Format extends PromptFormat {
  _Llama3Format()
      : super(
          PromptFormatType.raw,
          inputSequence: '<|start_header_id|>user<|end_header_id|>\n\n',
          outputSequence: '<|start_header_id|>assistant<|end_header_id|>\n\n',
          systemSequence: '<|start_header_id|>system<|end_header_id|>\n\n',
          stopSequence: '<|eot_id|>',
        );

  @override
  String formatPrompt(String prompt) {
    return '$inputSequence$prompt$stopSequence$outputSequence';
  }

  @override
  String formatMessages(List<Map<String, dynamic>> messages) {
    final buffer = StringBuffer();
    buffer.write('<|begin_of_text|>');

    for (final message in messages) {
      final role = message['role'];
      final content = message['content'] as String? ?? '';

      final header = switch (role) {
        'system' => systemSequence,
        'user' => inputSequence,
        'assistant' => outputSequence,
        _ => inputSequence,
      };
      buffer.write('$header$content$stopSequence\n');
    }

    // Prime assistant turn
    if (messages.isEmpty || messages.last['role'] != 'assistant') {
      buffer.write(outputSequence);
    }

    return buffer.toString();
  }
}
