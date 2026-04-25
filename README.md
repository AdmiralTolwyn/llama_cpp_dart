# LLAMA.CPP DART

> **Fork**: [AdmiralTolwyn/llama_cpp_dart](https://github.com/AdmiralTolwyn/llama_cpp_dart) — updated llama.cpp to latest master with full llama.rn feature parity.

A high-performance Dart binding for llama.cpp, enabling advanced text generation capabilities in both Dart and Flutter applications with flexible integration options.

## What's New in This Fork (v0.3.1)

| Feature | Status |
|---------|--------|
| **Latest llama.cpp** (~b8900+, Apr 2026) | All new model architectures (Gemma 4, Qwen 3.5, etc.) |
| **Grammar Sampling** (GBNF) | Constrain output to valid JSON via `SamplerParams.grammarStr` |
| **JSON Schema → GBNF** | `JsonSchemaToGbnf.convert(schema)` — auto-generate grammar from schema |
| **Tool Calling** | Parse OpenAI-style, `<tool_call>`, and Hermes/Qwen formats |
| **Vision / Multimodal** | libmtmd built and bundled for mmproj image understanding |
| **Parallel Decoding** | Queue-based API matching llama.rn (`enable`/`completion`/`disable`) |
| **Rerank API** | Document relevance scoring protocol |
| **LoRA Runtime Adapters** | Load/apply/remove GGUF LoRA adapters dynamically with per-adapter scaling |
| **Per-Arch Template Router** | `TemplateRouter.detectFromFilename()` — auto-select Gemma/Phi/Llama3/Qwen format |
| **Split Log Levels** | `Llama.setDartLogLevel()` / `setNativeLogLevel()` — independent Dart & native control |
| **Runtime Diagnostics** | `llama.getDiagnostics()` — backend name, GPU layers, model desc, param count |
| **Metal GPU** (iOS) | Compiled in, automatic |
| **OpenCL GPU** (Android) | Adreno 700+ |
| **Hexagon NPU** (Android) | Snapdragon 8 Gen 1+ (enable with `-DGGML_HEXAGON=ON`) |

### Usage via Git Dependency

```yaml
dependencies:
  llama_cpp_dart:
    git:
      url: https://github.com/AdmiralTolwyn/llama_cpp_dart.git
      ref: main
```

### Important: Batch Size Configuration

> **`nBatch` MUST equal `nCtx`**. The default batch size (512) silently rejects any prompt exceeding 512 tokens. Set it when creating context params:

```dart
final contextParams = ContextParams()
  ..nCtx = 32768
  ..nBatch = 32768; // Default 512 is too small for real prompts
```

### Important: Stream Lifecycle

Use `LlamaParent.completions` (not `stream.onDone`) to detect when generation finishes. The token `stream` is a broadcast `StreamController` that never fires `onDone`.

```dart
final promptId = await llamaParent.sendPrompt(prompt);
final completion = await llamaParent.completions
    .where((e) => e.promptId == promptId)
    .first;
// completion.success / completion.errorDetails
```

## Overview

This library provides three levels of abstraction for integrating llama.cpp into your Dart/Flutter projects, allowing you to choose the right balance between control and convenience:

1. **Low-Level FFI Bindings**: Direct access to llama.cpp functions
2. **High-Level Wrapper**: Simplified, object-oriented API
3. **Managed Isolate**: Flutter-friendly, non-blocking implementation

## Usage Examples

### Low-Level FFI Bindings
Direct llama.cpp integration with maximum control:
```dart
import 'package:llama_cpp_dart/src/core/llama_cpp.dart';

void main() {
  final lib = llama_cpp(DynamicLibrary.open("libllama.dylib"));
  // Initialize model, context, and sampling parameters
  // See examples/low_level.dart for complete example
}
```

check examples:
- [simple](example/simple.dart)
- [embedding](example/embedding_raw.dart)

### High-Level Wrapper
Simplified API for common use cases:
```dart
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

void main() {
  Llama.libraryPath = "libllama.dylib";
  final llama = Llama("path/to/model.gguf");
  
  llama.setPrompt("2 * 2 = ?");
  while (true) {
    var (token, done) = llama.getNext();
    print(token);
    if (done) break;
  }
  llama.dispose();
}
```

check examples:
- [test](example/test.dart)
- [rag](example/rag.dart)
- [chat](example/chat_cli.dart)


### Managed Isolate
Perfect for Flutter applications:
```dart
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

void main() async {
  final loadCommand = LlamaLoad(
    path: "path/to/model.gguf",
    modelParams: ModelParams(),
    contextParams: ContextParams(),
    samplingParams: SamplerParams(),
    format: ChatMLFormat(),
  );

  final llamaParent = LlamaParent(loadCommand);
  await llamaParent.init();

  llamaParent.stream.listen((response) => print(response));
  llamaParent.sendPrompt("2 * 2 = ?");
}
```

check examples:
- [test](example/test_isolated.dart)
- [chat](example/chat_cli_isolated.dart)

## Getting Started

### Prerequisites
- Dart SDK (for console applications)
- Flutter SDK (for Flutter applications)
- Compiled llama.cpp shared library

### Building llama.cpp Library

1. Clone the llama.cpp repository:
```bash
git clone https://github.com/ggml-org/llama.cpp
```

2. Compile into a shared library:
- Windows: Outputs .dll
- Linux: Outputs .so
- macOS: Outputs .dylib

check [BUILD.md](BUILD.md)

3. Place the compiled library in your project's accessible directory

## Installation

Add to your `pubspec.yaml`:
```yaml
dependencies:
  llama_cpp_dart: ^latest_version
```

## Model Selection Guide

When choosing and using LLM models with this library, consider the following:

### Use-Case Specific Models

Different models excel at different tasks:

- **Text Generation**: Most LLMs work well for general text generation.
- **Embeddings**: Not all models produce high-quality embeddings for semantic search. For example, while Gemma 3 can generate embeddings, it's not optimized for vector search. Instead, consider dedicated embedding models like E5, BGE, or SGPT.
- **Code Generation**: Models like CodeLlama or StarCoder are specifically trained for code.
- **Multilingual**: Some models have better support for non-English languages.

### Chat Formats

Each model family expects prompts in a specific format:

- **Llama 2**: Uses a specific format with `[INST]` and `[/INST]` tags
- **ChatML**: Used by models like Claude and GPT
- **Gemma**: Has its own system prompt format
- **Mistral/Mixtral**: Uses `<s>` tags in a particular way

Using the correct format is critical for optimal results. Our library provides common format templates:

```dart
// Example of setting the right chat format
final loadCommand = LlamaLoad(
  path: "path/to/llama2.gguf",
  format: Llama2ChatFormat(), // Choose the correct format for your model
);

// Other available formats
// ChatMLFormat()
// GemmaChatFormat()
// MistralChatFormat()
// Custom formats can be created by implementing the ChatFormat interface
```

### Model Size Considerations

Balance quality and performance:

- **7B models**: Fastest, lowest memory requirements, but less capable
- **13-14B models**: Good balance of performance and quality
- **30-70B models**: Highest quality, but significantly higher memory and processing requirements

### Quantization

Models come in different quantization levels that affect size, speed, and quality:

- **F16**: Highest quality, largest size
- **Q4_K_M**: Good balance of quality and size
- **Q3_K_M**: Smaller size, slightly reduced quality
- **Q2_K**: Smallest size, noticeable quality degradation

For most applications, Q4_K_M provides an excellent balance.

### Hardware Considerations

- **CPU**: All models work on CPU, but larger models require more RAM
- **Metal (Apple)**: Significant speed improvements on Apple Silicon
- **CUDA (NVIDIA)**: Best performance for NVIDIA GPUs
- **ROCm (AMD)**: Support for AMD GPUs

Ensure your compiled llama.cpp library includes support for your target hardware.

## JSON Schema Constrained Output

Force models to produce valid JSON matching a schema:

```dart
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

// Define the expected output schema
final grammar = JsonSchemaToGbnf.convert({
  'type': 'object',
  'properties': {
    'VERDICT': {'type': 'string', 'enum': ['TRADE', 'NO TRADE', 'WATCH']},
    'STRATEGY': {'type': 'string'},
    'CONVICTION': {'type': 'integer'},
    'RATIONALE': {'type': 'string'},
  },
  'required': ['VERDICT', 'STRATEGY', 'CONVICTION', 'RATIONALE'],
});

// Apply to sampler params
final samplerParams = SamplerParams()
  ..temp = 0.3
  ..grammarStr = grammar
  ..grammarRoot = 'root';
```

## Tool Calling

Parse tool calls from model output:

```dart
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

// Define tools
final tools = [
  ToolDefinition(
    name: 'get_weather',
    description: 'Get current weather for a city',
    parameters: {
      'type': 'object',
      'properties': {
        'city': {'type': 'string'},
      },
    },
  ),
];

// Inject into prompt
final toolsPrompt = ToolCallParser.buildToolsPrompt(tools);

// Parse model output
final calls = ToolCallParser.parse(modelOutput);
for (final call in calls) {
  print('Tool: ${call.name}, Args: ${call.arguments}');
}
```

## Template Router

Automatically select the correct `PromptFormat` for any model:

```dart
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

// From filename — use before the model is loaded (e.g. to show format in UI)
final format = TemplateRouter.detectFromFilename('gemma-3-4b-it-Q4_K_M.gguf');
// → GemmaFormat()

// From loaded GGUF metadata — highest accuracy
final format = TemplateRouter.detectFormat(
  model: llamaModelPtr,
  lib: Llama.lib,
  filename: model.filename, // optional filename fallback
);

final parent = LlamaParent(loadCommand, format);
```

| Family | Format | Key tokens |
|--------|--------|------------|
| Gemma 2/3/3n/4 | `GemmaFormat` | `<start_of_turn>` / `<end_of_turn>` |
| Phi 2/3/4/4-mini | `HarmonyFormat` | `<\|system\|>` / `<\|end\|>` |
| Llama 3/3.1/3.2/4 | `_Llama3Format` | `<\|begin_of_text\|>` / `<\|eot_id\|>` |
| Llama 2 / Alpaca | `AlpacaFormat` | `### Instruction:` |
| Qwen 2–3.5, Yi, Mistral, SmolLM | `ChatMLFormat` | `<\|im_start\|>` / `<\|im_end\|>` |

## Split Log Levels

Control Dart-side and native llama.cpp logs independently:

```dart
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

// During development: show native warnings only, suppress verbose Dart prints
Llama.setDartLogLevel(LlamaLogLevel.none);
Llama.setNativeLogLevel(LlamaLogLevel.warn);

// For debugging inference issues: full verbosity
Llama.setLogLevel(LlamaLogLevel.debug);

// In production: silence everything
Llama.setLogLevel(LlamaLogLevel.none);
```

Available levels: `none`, `debug`, `info`, `warn`, `error`.

## Runtime Diagnostics

Inspect a loaded model's runtime configuration:

```dart
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

final llama = Llama('model.gguf', modelParams: ModelParams()..nGpuLayers = 99);

final diag = llama.getDiagnostics();
print(diag.backendName);      // "Metal" | "CUDA" | "Vulkan" | "CPU"
print(diag.nGpuLayers);       // 99
print(diag.modelDesc);        // "llama 3.2 3B Q4_K_M"
print(diag.modelSizeBytes);   // 1910000000
print(diag.nParams);          // 3000000000
print(diag.nCtx);             // 8192
print(diag.isGpuAccelerated); // true

// Convenience accessors:
print(llama.getBackendName());        // "Metal"
print(llama.getResolvedGpuLayers());  // 99
```

## LoRA Runtime Adapters

Load and apply GGUF LoRA adapters without reloading the base model:

```dart
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

final llama = Llama('base-model.gguf');

// Load adapter
final adapter = LoraAdapter.load(llama.model, 'path/to/adapter.gguf');

// Apply with scaling (0.0–1.0)
llama.setLora(adapter, scale: 0.8);

// Swap scale dynamically
llama.setLora(adapter, scale: 0.4);

// Remove adapter (does NOT free memory)
llama.rmLora(adapter);

// Remove all adapters
llama.clearLoras();

// Free native memory when fully done
adapter.dispose();
```

Multiple adapters can be active simultaneously. Each shares the base model's weight memory — no extra RAM for the base weights.

## Parallel Decoding

Queue multiple requests:

```dart
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

final decoder = ParallelDecoder(generate: myGenerateFunction);
decoder.enable(nParallel: 4);

final r1 = decoder.completion('What is AI?', onToken: (t) => print(t));
final r2 = decoder.completion('Explain quantum computing');

final result1 = await r1.promise;
final result2 = await r2.promise;

decoder.disable();
```

## License

This project is licensed under the MIT License - see the `LICENSE.md` file for details.