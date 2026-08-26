## 0.4.0 (AdmiralTolwyn fork)

### Per-prompt GBNF grammar override

`SamplerParams` only ever travelled on the load command, so constraining a
generation to a grammar meant re-reading the entire model. For a resident
multi-gigabyte model that is a per-request reload. The grammar now rides the
**prompt**.

* **`LlamaParent.sendPrompt(prompt, {grammarStr, grammarRoot})`** — and the
  same two optional named parameters on `sendPromptWithImages` and on both
  `LlamaScope` variants. They are threaded verbatim onto the new
  `LlamaPrompt.grammarStr` / `LlamaPrompt.grammarRoot` fields.
  - `null` (default) — keep whatever grammar the load-time `SamplerParams`
    carried. Byte-for-byte the previous behaviour, load-time grammars included.
  - `''` — explicitly unconstrained, dropping any load-time grammar.
  - GBNF — constrain this one generation.
  - `grammarRoot` defaults to the conventional `root` rule.
* **`Llama.applyGrammar(String? grammarStr, {String? grammarRoot})`** — the
  core-side swap. It rebuilds the sampler chain **only when the effective
  grammar actually changes**: consecutive grammar-less prompts and consecutive
  prompts carrying the identical grammar string cost nothing. `Llama` retains a
  copy of the load-time `SamplerParams` (new `SamplerParams.copy()`) and every
  rebuild starts from that copy with only the grammar fields replaced, so
  reverting restores exactly the chain built at load.
* **Grammar samplers are stateful across tokens.** When the chain is reused
  unchanged under an active grammar, `llama_sampler_reset` is issued first —
  `llama_sampler_chain_reset` propagates to every member and the grammar
  sampler re-parses its GBNF back to the start state. Without this, the second
  generation under the same grammar would resume in the previous one's terminal
  state and mask every token. Unconstrained sessions are untouched.

### Fixed

* **A grammar was silently ignored in greedy mode.** `SamplerFactory.build`
  returned early for `params.greedy`, before the grammar block ever ran — so
  tuned, near-greedy models could not be constrained at all. The grammar
  sampler is now added **first**, ahead of the early return: it masks
  grammar-illegal tokens to `-INF`, and whatever selects the token afterwards
  (the greedy argmax, or `dist` at the end of the full chain) only ever sees
  legal candidates. Chain composition with an empty grammar is unchanged:
  `[greedy]` for greedy, `[penalties … dist]` otherwise.
* **A grammar with no named root rule is no longer discarded.** An empty
  `grammarRoot` now falls back to `root` (`kDefaultGrammarRoot`) instead of
  handing llama.cpp an empty root name, which always returned `nullptr`.

### Robustness

* **Bad GBNF degrades; it never crashes or wedges the isolate.**
  `llama_sampler_init_grammar` returns `nullptr` on invalid GBNF or an unknown
  root rule. `SamplerFactory.build` reports that through a new optional
  `onGrammarError` callback and returns a complete, valid, *unconstrained*
  chain — never a half-built one. `applyGrammar` returns the message rather
  than throwing, marks the grammar inactive (so a retry recompiles instead of
  being skipped as a no-op), and leaves generation running.
* **The swap is leak-free and exception-safe.** The replacement chain is built
  first; only once it is known good is `_smpl` reassigned and the old chain
  passed to `llama_sampler_free`. If the rebuild throws or yields a null chain,
  the existing known-good sampler is kept and the reason is returned.
* **Non-fatal notice on the existing channel.** The child warns via
  `LlamaLogger.warn` (matching the existing `_handleFreeSlot` precedent) and
  carries the reason as `errorDetails` on the terminal `LlamaStatus.ready`
  response. It surfaces on `CompletionEvent.errorDetails` with
  `success == true`; `LlamaParent` only treats `errorDetails` as fatal when the
  status is `error`, so nothing throws.

### Tests

* `test/grammar_override_test.dart` — 4 unit tests: `SamplerParams.copy()`
  field-for-field fidelity and `dryBreakers` deep-copy independence,
  `LlamaPrompt` grammar fields defaulting to null.
* `test/integration/grammar_override_integration_test.dart` — 18 real-model
  tests (`stories260K.gguf`, tagged `integration`): constrain-then-revert in one
  session, identical-grammar no-rebuild via the new
  `Llama.samplerRebuildCount` test seam, invalid GBNF and missing-root-rule
  degradation, grammar under greedy *and* non-greedy sampling, load-time
  grammar preservation, end-to-end through `LlamaParent.sendPrompt`, and
  `SamplerFactory` chain-composition assertions read back out of the native
  chain with `llama_sampler_chain_n` / `llama_sampler_name`.

### Dependencies

* Added `meta` (for `@visibleForTesting` on `Llama.samplerRebuildCount`).

## 0.3.10 (AdmiralTolwyn fork)

### Integration Tests
* **11 real-model integration tests** — `test/integration/llama_integration_test.dart`
  loads `stories260K.gguf` (1.2 MB, ggml-org/models, MIT) via the
  `bin/MAC_ARM64/libllama.dylib` native binary and exercises:
  - Model loading + `LlamaDiagnostics`
  - Tokenization (addBos, empty-text guard)
  - Streaming and complete text generation (greedy / deterministic)
  - Context clear + re-prompt reproducibility
  - Remaining-context-space accounting
  - Dispose guards (single + double dispose)
* **Tag-gated** — tests are tagged `integration` via `dart_test.yaml`.
  CI runs `flutter test --exclude-tags integration` (no native lib on
  ubuntu). Run locally: `flutter test --tags integration`.

## 0.3.9 (AdmiralTolwyn fork)

### Hygiene Pass
* **`llama.cpp` submodule no longer floats on `master`** — `.gitmodules`
  removed the `branch = master` directive. The submodule is now pinned via the
  tracked commit (currently tag `b8920`) like any normal git submodule, so a
  fresh clone reproduces the same llama.cpp source on every machine. Use
  `./update_submodules.sh` to advance to a newer release intentionally.
* **CI added** — `.github/workflows/ci.yml` runs `dart analyze lib/` and
  `flutter test` on every push and PR. No more "compiles on Anton's MacBook"
  surprises shipping to consumers.
* **`LICENSE` attribution** — added a fork copyright line alongside the
  original. The MIT terms are unchanged.
* **`print()` → `LlamaLogger`** — the 35 raw `print()` calls scattered across
  `llama.dart`, `llama_service.dart`, `llama_session_io.dart`, the isolate
  files, and `mcp_client.dart` now go through `LlamaLogger.info/warn/error`.
  Output is gated by `LlamaLogger.setDartLogLevel(...)`. Setting
  `LlamaLogLevel.none` (the default) silences the bindings completely;
  previously you had to live with the prints.
* **`ContextParams.nBatch` doc warning** — the field now carries a doc comment
  explaining the historical `Prompt tokens > batch capacity` footgun and the
  recommended `nBatch == nCtx` pattern. Behaviour unchanged (chunked prefill
  from 0.3.4 still handles the smaller-`nBatch` case correctly).

## 0.3.8 (AdmiralTolwyn fork)

### Bug Fixes
* **`LlamaParent.dispose()` use-after-close race** — the previous order closed
  `_controller` and `_completionController` *before* cancelling the child
  isolate subscription, then awaited 50ms for the child to drain. Any token
  or completion event the child emitted during that window threw
  `Bad state: Cannot add new events after calling close`. Dispose now sends
  `LlamaDispose`, drains for 50ms, cancels the subscription, and only then
  closes the broadcast controllers. Defensive `isClosed` checks were also
  added in `_onData` for the text and completion branches.
* **`_operationCompleter` silent drop on collision** — `_sendCommand()`
  blindly reassigned `_operationCompleter` on every call. If a previous
  command (e.g. `loadState()`) was still pending when `clear()` was issued,
  the previous future would only resolve via its 30s/60s timeout. Now any
  pending operation is explicitly completed with a
  `StateError('Operation superseded by: ...')` before being replaced.
* **`Llama.setPrompt()` chunked prefill: stale `_nPos` on mid-chunk failure**
  — if `llama_decode` returned non-zero on a non-final chunk, `_nPos` was
  left advanced for the chunks already decoded, while the catch block only
  freed the token buffer. A caller that recovered from the exception and
  retried `setPrompt()` would silently lay the new prompt at a stale offset,
  producing garbage. The chunked path now snapshots `_nPos` and, on any
  decode failure, clears the KV cache and restores the snapshot before
  rethrowing.
* **`LlamaParent._processNextPrompt()` magic 10ms race** — the previous
  `await stop(); await Future.delayed(10ms)` between consecutive prompts
  raced on slow devices: the next `LlamaPrompt` could land while the child
  was still draining the prior generation, causing tokens to be tagged with
  the wrong `promptId`. The 10ms sleep is replaced with an actual await on
  the previous prompt's completion future (capped at 2s as a defensive
  ceiling).

### API Honesty
* **`ParallelDecoder` no longer claims to be parallel** — the implementation
  is and always was a strict FIFO that calls the supplied `_generate` once
  at a time. The class docs, `nParallel` parameter, and `slotCount` getter
  now state explicitly that the value is accepted for llama.rn API parity
  but is not honoured. For real concurrency, use `LlamaService` with seq_id
  slots. `ParallelRequest.fail()` now resolves with `completeError(...)`
  instead of `complete(null)` so callers can distinguish failure from an
  empty model response.

### Native Packaging
* **Android `minSdk`/`compileSdk` alignment** — `android/build.gradle`
  declared `minSdkVersion 23` while `android/llamalib/build.gradle`
  declared `minSdk 24` and `compileSdk 36`. Consumer apps targeting SDK 23
  hit Gradle resolution failures. Both files now declare `minSdk 24` and
  `compileSdk 34`.
* **`darwin/fix_rpath.sh` no longer bakes an absolute build-machine path**
  into the macOS dylib's rpath. Builds are now reproducible across machines
  and the dylib survives relocation (the `@loader_path/Frameworks` and
  `@executable_path/Frameworks` entries already cover bundle embedding).

## 0.3.6 (AdmiralTolwyn fork)

### New Features
* **`ChatMLFormat(noThink: true)`** — appends an empty `<think>\n\n</think>\n\n`
  block immediately after every `<|im_start|>assistant\n` opener. This is the
  canonical Qwen 3 "thinking off" trick (equivalent to `enable_thinking=False`
  in the official Jinja template) and forces the model to skip chain-of-thought
  and answer directly. Without it, Qwen 3 / DeepSeek-R1 distills emit long
  `<think>...</think>` sections that can burn through the entire context window
  before producing any real output.

* **`TemplateRouter` auto-detection of thinking models** — Qwen 3, Qwen 3.5,
  QwQ, DeepSeek-R1, and R1-distill filenames now route to `ChatMLFormat(noThink:
  true)` automatically. Qwen 2 / 2.5 and base DeepSeek keep plain ChatML.

## 0.3.5 (AdmiralTolwyn fork)

### Bug Fixes
* **Chunked prefill: position math** — 0.3.4 advanced `_nPos` after each chunk
  *and* used it when computing `batch.pos[i]` for the next chunk, double-counting
  the offset. Result: `Failed to decode prompt chunk at offset 512` on the
  second chunk. Fixed by snapshotting `_nPos` once at the start of the chunked
  loop and computing positions relative to that snapshot.

## 0.3.4 (AdmiralTolwyn fork)

### Bug Fixes
* **Chunked prompt prefill** — `Llama.setPrompt()` no longer throws
  `Prompt tokens (N) > batch capacity (M)` when the prompt exceeds `nBatch`.
  The wrapper now splits long prompts into `nBatch`-sized chunks and decodes
  them sequentially via `llama_decode`, leaving only the final chunk primed in
  the batch for `getNext()` to sample. This matches what `llama.rn` and
  `llama.cpp`'s CLI do natively.

  Practical impact: callers can now keep `nBatch` small (e.g. 512) without
  losing the ability to send multi-thousand-token prompts. Previously the only
  workaround was `nBatch = nCtx`, which inflates the per-layer compute buffer
  and OOMs large models (4B+) on memory-constrained devices like iPhone.

## 0.3.3 (AdmiralTolwyn fork)

### New Features
* **Multi-platform plugin declaration** — `pubspec.yaml` now declares the
  package as a Flutter plugin for Android, iOS, macOS, Linux, and Windows.

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
