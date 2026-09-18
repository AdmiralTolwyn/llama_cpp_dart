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

    // Ask the live ggml-backend device registry rather than parsing
    // llama_print_system_info()'s text: that string is compile-flag
    // formatted (e.g. "METAL = 1") and this engine line registers its
    // Metal device as "MTL" ("MTL : EMBED_LIBRARY = 1"), so the old
    // substring match never hit and every GPU run silently reported
    // "CPU" even with 35/35 layers offloaded to Metal.
    try {
      final devCount = lib.ggml_backend_dev_count();
      for (var i = 0; i < devCount; i++) {
        final dev = lib.ggml_backend_dev_get(i);
        final type = lib.ggml_backend_dev_type$1(dev);
        // GPU/IGPU devices hold offloaded layers; ACCEL (e.g. BLAS) and
        // CPU devices pair with the CPU backend and never do.
        if (type != ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU &&
            type != ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_IGPU) {
          continue;
        }
        final reg = lib.ggml_backend_dev_backend_reg(dev);
        final regName =
            lib.ggml_backend_reg_name(reg).cast<Utf8>().toDartString();
        return _friendlyBackendName(regName);
      }
    } catch (_) {
      // If the device registry can't be walked, fall through to CPU.
    }
    return 'CPU';
  }

  /// Maps a ggml backend registry name (e.g. "MTL", "CUDA0") to the
  /// human-readable label diagnostics consumers expect. Falls back to the
  /// registry's own name for a backend not in this table, rather than
  /// silently reporting "CPU" for a GPU that IS active.
  static String _friendlyBackendName(String regName) {
    final upper = regName.toUpperCase();
    if (upper.startsWith('MTL') || upper.startsWith('METAL')) return 'Metal';
    if (upper.startsWith('CUDA')) return 'CUDA';
    if (upper.startsWith('VK') || upper.startsWith('VULKAN')) return 'Vulkan';
    if (upper.startsWith('SYCL')) return 'SYCL';
    if (upper.startsWith('HIP') || upper.startsWith('ROCM')) return 'ROCm';
    if (upper.startsWith('OPENCL') || upper.startsWith('CL')) return 'OpenCL';
    return regName;
  }
}
