import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'llama.dart' show Llama;
import 'llama_cpp.dart';

/// Runtime diagnostic information about a loaded model and its context.
class LlamaDiagnostics {
  /// Human-readable description of the model (e.g. "llama 3B Q4_K_M").
  final String modelDesc;

  /// Model file size in bytes (compressed weight storage).
  final int modelSizeBytes;

  /// Total number of parameters in the model.
  final int nParams;

  /// Vocab size (number of tokens in the model vocabulary).
  final int nVocab;

  /// The context size the runtime was configured with.
  final int nCtx;

  /// Number of GPU layers offloaded (0 = CPU-only).
  final int nGpuLayers;

  /// Human-readable backend name — "Metal", "CUDA", "CPU", etc.
  /// Returns "CPU" if backend name cannot be resolved.
  final String backendName;

  /// Whether vision/multimodal is active.
  final bool visionEnabled;

  const LlamaDiagnostics({
    required this.modelDesc,
    required this.modelSizeBytes,
    required this.nParams,
    required this.nVocab,
    required this.nCtx,
    required this.nGpuLayers,
    required this.backendName,
    required this.visionEnabled,
  });

  /// Approximate GPU layers that are actually running on the accelerator.
  /// On Apple Silicon, Metal offloads all layers when nGpuLayers > 0.
  bool get isGpuAccelerated => backendName != 'CPU' && nGpuLayers > 0;

  @override
  String toString() =>
      'LlamaDiagnostics(model="$modelDesc", backend=$backendName, '
      'gpuLayers=$nGpuLayers, nCtx=$nCtx, params=${(nParams / 1e9).toStringAsFixed(2)}B, '
      'sizeGB=${(modelSizeBytes / 1e9).toStringAsFixed(2)})';
}

/// Provides diagnostic and runtime introspection helpers on a loaded [Llama] instance.
///
/// Usage:
/// ```dart
/// final diag = LlamaRuntime.getDiagnostics(llamaInstance);
/// print(diag.backendName);  // "Metal"
/// print(diag.nGpuLayers);   // 99
/// ```
class LlamaRuntime {
  /// Returns runtime diagnostics for a loaded [Llama] instance.
  ///
  /// Must be called after [Llama] construction (model loaded).
  static LlamaDiagnostics getDiagnostics(
    Pointer<llama_model> model,
    Pointer<llama_context> ctx,
    Pointer<llama_vocab> vocab,
    int nGpuLayers, {
    bool visionEnabled = false,
  }) {
    final lib = Llama.lib;

    // Model description
    final descBuf = calloc<Char>(256);
    lib.llama_model_desc(model, descBuf, 256);
    final modelDesc = descBuf.cast<Utf8>().toDartString();
    calloc.free(descBuf);

    // Model size
    final sizeBytes = lib.llama_model_size(model);

    // Param count
    final nParams = lib.llama_model_n_params(model);

    // Vocab
    final nVocab = lib.llama_n_vocab(vocab);

    // Context window
    final nCtx = lib.llama_n_ctx(ctx);

    // Backend name
    final backendName = _resolveBackendName(lib, nGpuLayers);

    return LlamaDiagnostics(
      modelDesc: modelDesc,
      modelSizeBytes: sizeBytes,
      nParams: nParams,
      nVocab: nVocab,
      nCtx: nCtx,
      nGpuLayers: nGpuLayers,
      backendName: backendName,
      visionEnabled: visionEnabled,
    );
  }

  static String _resolveBackendName(llama_cpp lib, int nGpuLayers) {
    if (nGpuLayers <= 0) return 'CPU';

    // llama.cpp provides a system info string that includes backend names
    try {
      final ptr = lib.llama_print_system_info();
      if (ptr != nullptr) {
        final info = ptr.cast<Utf8>().toDartString();
        // Parse "METAL = 1" / "CUDA = 1" / "Vulkan = 1" from system info
        if (info.contains('METAL = 1') || info.contains('Metal = 1')) {
          return 'Metal';
        }
        if (info.contains('CUDA = 1') || info.contains('cuda = 1')) {
          return 'CUDA';
        }
        if (info.contains('VULKAN = 1') || info.contains('Vulkan = 1')) {
          return 'Vulkan';
        }
        if (info.contains('OpenCL = 1') || info.contains('OPENCL = 1')) {
          return 'OpenCL';
        }
        if (info.contains('BLAS = 1')) {
          return 'BLAS';
        }
      }
    } catch (_) {
      // If llama_print_system_info fails, fall through to CPU
    }
    return 'CPU';
  }
}
