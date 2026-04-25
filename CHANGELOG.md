## 0.3.2 (AdmiralTolwyn fork)

### New Features
* **`LlamaParent.clear()`** — Clears the KV cache and resets context state without unloading the model.
  Use this to recover memory after a native inference error (`ggml_abort`, OOM, SIGABRT):
  ```dart
  try {
    final result = await llamaParent.sendPrompt(prompt);
  } catch (e) {
    if (isNativeCrash(e)) {
      await llamaParent.clear(); // reset KV cache, model stays loaded
    }
  }
  ```
  Sends `LlamaClear` to the isolate, which calls `llama.clear()` natively and confirms readiness.

## 0.3.1 (AdmiralTolwyn fork)

### New Features
* **Split Log Levels** (`LlamaLogger`) — Control Dart-side and native llama.cpp logs independently.
  ```dart
  Llama.setDartLogLevel(LlamaLogLevel.info);     // Dart bindings verbosity
  Llama.setNativeLogLevel(LlamaLogLevel.warn);   // native llama.cpp / ggml logs
  Llama.setLogLevel(LlamaLogLevel.none);         // silence everything
  ```
  Available levels: `none`, `debug`, `info`, `warn`, `error`.

* **Runtime Diagnostics** (`LlamaRuntime`, `LlamaDiagnostics`) — Introspect a loaded model at runtime.
  ```dart
  final diag = llamaInstance.getDiagnostics();
  print(diag.backendName);     // "Metal" | "CUDA" | "CPU"
  print(diag.nGpuLayers);      // 99
  print(diag.modelDesc);       // "llama 3.2 3B Q4_K_M"
  print(diag.modelSizeBytes);  // 1910000000
  print(diag.nParams);         // 3000000000
  print(diag.nCtx);            // 8192
  print(diag.isGpuAccelerated); // true
  // convenience accessors also on Llama directly:
  llamaInstance.getBackendName();       // "Metal"
  llamaInstance.getResolvedGpuLayers(); // 99
  ```

* **LoRA Runtime Adapters** (`LoraAdapter`, `LoraAdapterMixin`) — Load and apply GGUF LoRA adapters dynamically.
  ```dart
  final adapter = LoraAdapter.load(llama.model, 'path/to/adapter.gguf');
  llama.setLora(adapter, scale: 0.8);   // apply with scaling
  llama.rmLora(adapter);                // remove without freeing
  llama.clearLoras();                   // remove all
  adapter.dispose();                    // free native memory
  ```
  Multiple adapters share the base model memory. Scale can be adjusted dynamically.

* **Per-Architecture Template Router** (`TemplateRouter`) — Automatically selects the correct `PromptFormat` from a model filename or loaded model metadata. Eliminates manual format selection.
  ```dart
  // From filename (before model loads — e.g. for UI display):
  final format = TemplateRouter.detectFromFilename('gemma-3-4b-it-Q4_K_M.gguf');
  // → GemmaFormat()

  // From loaded model (uses GGUF metadata for highest accuracy):
  final format = TemplateRouter.detectFormat(
    model: llamaModelPtr,
    lib: Llama.lib,
    filename: model.filename, // optional fallback
  );

  final parent = LlamaParent(loadCommand, format);
  ```
  Routing table:
  | Family | Format | Tokens |
  |--------|--------|--------|
  | Gemma 2/3/3n/4 | `GemmaFormat` | `<start_of_turn>` / `<end_of_turn>` |
  | Phi 2/3/4/4-mini | `HarmonyFormat` | `<\|system\|>` / `<\|end\|>` |
  | Llama 3/3.1/3.2/4 | `_Llama3Format` | `<\|begin_of_text\|>` / `<\|eot_id\|>` |
  | Llama 2 / Alpaca | `AlpacaFormat` | `### Instruction:` |
  | Qwen 2/2.5/3/3.5, Yi, Mistral, SmolLM | `ChatMLFormat` | `<\|im_start\|>` / `<\|im_end\|>` |
  | (default fallback) | `ChatMLFormat` | — |

* **`HarmonyFormat` now exported** — Previously used internally; now exported via the main barrel for Phi-family models.

### Infrastructure
* Bumped version to 0.3.1
* Exported new modules: `llama_log_level.dart`, `llama_diagnostics.dart`, `lora_adapter.dart`, `template_router.dart`, `harmony_format.dart`
* `Llama` now uses `with LoraAdapterMixin` — LoRA methods available directly on any `Llama` instance
* `Llama._nGpuLayers` stored at load time from `ModelParams.nGpuLayers` (was not accessible after construction)

---

## 0.3.0 (AdmiralTolwyn fork)

### CRITICAL: nBatch Configuration
* **`ContextParams.nBatch` MUST be set to match `nCtx`**. The default (512) silently rejects any prompt exceeding 512 tokens with `LlamaException: Prompt tokens (N) > batch capacity (512)`. This affects ALL models and causes 0-char responses.

```dart
final contextParams = ContextParams()
  ..nCtx = 32768
  ..nBatch = 32768; // MUST match nCtx
```

### llama.cpp Update
* **Updated llama.cpp** from b7807 (Jan 2025) to latest master (~b8900+, Apr 2026)
* All new model architectures now supported: **Gemma 4** (PLE), **Qwen 3.5** (Gated DeltaNet + MoE), and all models released since Jan 2025

### New Features
* **JSON Schema → GBNF converter** (`JsonSchemaToGbnf.convert()`) — Converts JSON Schema objects to GBNF grammar strings for constrained output generation. Supports object, array, string, number, integer, boolean, enum, const, oneOf/anyOf. Includes `simpleObject()` helper.
* **Tool Calling** (`ToolCallParser`) — Parses tool calls from model output in 3 formats: OpenAI-style JSON, `<tool_call>` XML tags, and Hermes/Qwen style. Includes `ToolDefinition`, `ToolCall`, `ToolResult` classes and `buildToolsPrompt()` / `formatToolResult()` helpers.
* **Parallel Decoding** (`ParallelDecoder`) — Queue-based parallel request processing matching llama.rn's `context.parallel` API (`enable`, `completion`, `disable`). Sequential queue now; native multi-slot via FFI in future.
* **Reranker API** (`Reranker`, `NoOpReranker`) — Protocol for document relevance scoring matching llama.rn's `context.rerank()`. Uses `LLAMA_POOLING_TYPE_RANK` with `llama_encode` + embeddings.

### iOS Build Fixes
* **Patched cpp-httplib** for iOS — guarded `SecTrustCopyAnchorCertificates` with `__IPHONE_OS_VERSION_MIN_REQUIRED` check (function unavailable on iOS)
* **Disabled OpenSSL** for iOS builds (`-DLLAMA_OPENSSL=OFF`) — prevents macOS Homebrew OpenSSL from linking into iOS binaries
* Re-enabled `LLAMA_BUILD_COMMON` + `LLAMA_BUILD_TOOLS` for libmtmd (multimodal/vision)
* XCFramework now includes **libmtmd.dylib** (912 KB) for vision/multimodal support

### Android
* Added `<uses-native-library android:name="libcdsprpc.so">` for Hexagon NPU acceleration (Snapdragon 8 Gen 1+)
* Hexagon NPU can be enabled with `-DGGML_HEXAGON=ON` in Android builds

### Infrastructure
* Bumped version to 0.3.0
* Updated homepage/repository URLs to AdmiralTolwyn fork
* Exported new modules: `tool_calling.dart`, `parallel_decoder.dart`, `json_schema_to_gbnf.dart`, `reranker.dart`

## 0.2.3
*  **Performance**: Moved image embedding storage to native memory (C heap) to reduce Dart GC pressure and improve stability with high-resolution images.
*  Fix memory leaks in session cancellation and disposal logic.

## 0.2.2- allow freeing the active slot by switching/detaching and reselecting a fallback
*  ensure isolate child always replies on dispose/free, even when already torn down
*  keep parent subscription alive through shutdown so free-slot confirmations are received
*  cancel scope work before freeing slots to avoid in-flight races
*  add opt-in KV auto-trim (sliding window) with example `example/auto_trim.dart`

## 0.2.1
* **Android**: Added OpenCL support for GPU acceleration (#91).
* **Vision**: 
    * Fixed crash in `mtmd` context disposal.
    * Stable Qwen3-VL support.
* **Chat**: Added experimental support for Qwen3-VL chat format (`_exportQwen3Jinja`).
* **Fixes**:
    * Improved logging initialization (#88).
    * Fixed stream processing crash in chat.
* **Core**: Updated `llama.cpp` submodule.

## 0.2.0
* llama.cpp 4ffc47cb2001e7d523f9ff525335bbe34b1a2858
* Memory Safety: No more pointer being freed was not allocated crashes.
* UTF-8 Safety: Emojis and foreign languages won't break generation.
* Context Management: You can Append, Clear, or Save the brain.
* Multi-Tenancy: You can handle multiple users (Slots) if you need to.
* breakign changes:
    Old: Llama(path, modelParams, contextParams, samplerParams, verbose)
    New: Llama(path, modelParams: ..., contextParams: ..., samplerParams: ..., verbose: ...)
* Parameter Serialization: ContextParams and ModelParams JSON serialization has changed. Enums (like LlamaRopeScalingType) now store their specific C-API integer values instead of Dart list indices. Old JSON configs may need migration.
* Sampler Standardization: SamplerParams has been refactored to strictly match llama.cpp. Non-standard fields (e.g., xtcTemperature, topPKeep) have been renamed or removed.
* RPC Removed: Removed rpcServers from ModelParams as it is no longer supported in the core struct.


## 0.1.2+1
* forgot to update version

## 0.1.2
* removed flash_attn llama_context_default_params
* removed softmax
* updated llama.cpp to b8595b16e

## 0.1.1
* State load / save
* llama.cpp 25ff6f7659f6a5c47d6a73eada5813f0495331f0
* harmony prompting syntax
* isolate has vision and verbose support 
* mcp server / agent
* scope generation stopping

## 0.1.0
* Multimodal support - vision

## 0.0.9
* Major internal refactoring to improve code organization and maintainability
* Fixed critical bug where subsequent prompts would fail due to batch seq_id memory management
* Improved position tracking for continuous conversation support
* Enhanced error handling and debugging capabilities
* Added foundation for future chat optimization features
* Breaking change: Internal API restructuring (public API remains stable)

## 0.0.8
* disabled llava
* compatible with llama.cpp 42ae10bb
* add typed_isolate
* removed llama processor

## 0.0.7
* updated binding
* performance imporvement and bugs fix

## 0.0.6

* added initial support to load lora
* dart cli example
* fixed #3 by @danemadsen

## 0.0.5

* removed assets defination
* added static property `Llama.libraryPath` to set library path, in order to support linux and other platforms

## 0.0.4

* `ModelParams` disabled options `splitsMode`, `tensorSplit` and `metadataOverride`

## 0.0.3

* LlamaProcessor now take context and model parameters

## 0.0.2

* refactored code to follow dart package structure

## 0.0.1

* TODO: Describe initial release.
