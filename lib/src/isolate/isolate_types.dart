import 'dart:typed_data';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

/// Base class for commands sent to the LlamaChild isolate
sealed class LlamaCommand {}

class LlamaStop extends LlamaCommand {}

class LlamaClear extends LlamaCommand {}

class LlamaDispose extends LlamaCommand {}

class LlamaSaveState extends LlamaCommand {
  final String slotId;
  LlamaSaveState(this.slotId);
}

class LlamaLoadState extends LlamaCommand {
  final String slotId;
  final Uint8List data;
  LlamaLoadState(this.slotId, this.data);
}

class LlamaLoadSession extends LlamaCommand {
  final String slotId;
  final String path;
  LlamaLoadSession(this.slotId, this.path);
}

class LlamaFreeSlot extends LlamaCommand {
  final String slotId;
  LlamaFreeSlot(this.slotId);
}

class LlamaEmbedd extends LlamaCommand {
  final String prompt;
  LlamaEmbedd(this.prompt);
}

/// Count tokens for [text] with the loaded model's real tokenizer.
/// Vocab-only — no inference, no KV-cache interaction; safe to call
/// between generations. Response arrives as [LlamaResponse.tokenCount].
class LlamaTokenizeCount extends LlamaCommand {
  final String text;
  final bool addBos;
  LlamaTokenizeCount(this.text, {this.addBos = true});
}

class LlamaInit extends LlamaCommand {
  final String? libraryPath;
  LlamaInit(this.libraryPath);
}

class LlamaPrompt extends LlamaCommand {
  final String prompt;
  final String promptId;
  final List<LlamaImage>? images;
  final String? slotId;

  /// Per-prompt GBNF grammar constraining this generation.
  ///
  /// `null` keeps whatever grammar the model was loaded with (the default, and
  /// byte-for-byte the previous behaviour); `''` explicitly drops it; a GBNF
  /// string constrains this one generation. The child swaps the sampler chain
  /// in place, so a resident multi-gigabyte model never has to be reloaded to
  /// change the grammar.
  final String? grammarStr;

  /// Root rule of [grammarStr]. Defaults to the conventional `root`.
  final String? grammarRoot;

  LlamaPrompt(
    this.prompt,
    this.promptId, {
    this.images,
    this.slotId,
    this.grammarStr,
    this.grammarRoot,
  });
}

class LlamaLoad extends LlamaCommand {
  final String path;
  final ModelParams modelParams;
  final ContextParams contextParams;
  final SamplerParams samplingParams;
  final bool verbose;
  final String? mmprojPath;

  LlamaLoad({
    required this.path,
    required this.modelParams,
    required this.contextParams,
    required this.samplingParams,
    this.verbose = false,
    this.mmprojPath,
  });
}

class LlamaResponse {
  final String text;
  final bool isDone;
  final LlamaStatus? status;
  final String? promptId;
  final String? errorDetails;
  final bool isConfirmation;
  final List<double>? embeddings;

  /// Result of a [LlamaTokenizeCount] command (see parent `countTokens`).
  final int? tokenCount;

  final Uint8List? stateData;

  LlamaResponse({
    required this.text,
    required this.isDone,
    this.status,
    this.promptId,
    this.errorDetails,
    this.isConfirmation = false,
    this.embeddings,
    this.tokenCount,
    this.stateData,
  });

  factory LlamaResponse.confirmation(LlamaStatus status, [String? promptId]) {
    return LlamaResponse(
      text: "",
      isDone: false,
      status: status,
      promptId: promptId,
      isConfirmation: true,
    );
  }

  factory LlamaResponse.stateData(Uint8List data) {
    return LlamaResponse(
      text: "",
      isDone: true,
      stateData: data,
    );
  }

  factory LlamaResponse.error(String errorMessage, [String? promptId]) {
    return LlamaResponse(
      text: "",
      isDone: true,
      status: LlamaStatus.error,
      promptId: promptId,
      errorDetails: errorMessage,
    );
  }
}
