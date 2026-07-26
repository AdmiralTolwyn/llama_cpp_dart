import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'llama.dart' show Llama;
import 'llama_types.dart' show LlamaException;
import 'llama_cpp.dart';

/// A loaded LoRA adapter that can be applied to a model context at runtime.
///
/// Load via [LoraAdapter.load], apply via [Llama.setLora], remove via [Llama.rmLora].
/// Always call [dispose] when done to free native memory.
class LoraAdapter {
  final Pointer<llama_adapter_lora> _ptr;
  final String path;
  bool _disposed = false;

  LoraAdapter._(this._ptr, this.path);

  /// Loads a LoRA adapter from [loraPath] against [model].
  ///
  /// Throws [LlamaException] if the file cannot be loaded.
  static LoraAdapter load(Pointer<llama_model> model, String loraPath) {
    final pathPtr = loraPath.toNativeUtf8().cast<Char>();
    try {
      final ptr = Llama.lib.llama_adapter_lora_init(model, pathPtr);
      if (ptr == nullptr) {
        throw LlamaException('Failed to load LoRA adapter from: $loraPath');
      }
      return LoraAdapter._(ptr, loraPath);
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// Whether this adapter has been disposed.
  bool get isDisposed => _disposed;

  Pointer<llama_adapter_lora> get nativePtr {
    if (_disposed) throw StateError('LoraAdapter has been disposed');
    return _ptr;
  }

  /// Frees the native LoRA adapter memory. Must be called after removing from all contexts.
  void dispose() {
    if (!_disposed) {
      Llama.lib.llama_adapter_lora_free(_ptr);
      _disposed = true;
    }
  }

  @override
  String toString() => 'LoraAdapter(path=$path, disposed=$_disposed)';
}

/// Mixin providing LoRA adapter management on a class that holds a [llama_context].
///
/// Applied to [Llama] — exposes [setLora], [rmLora], [clearLoras].
mixin LoraAdapterMixin {
  Pointer<llama_context> get context;

  /// Currently-applied adapters and their scales.
  ///
  /// Upstream (llama.cpp b8920+) replaced the incremental
  /// `llama_set_adapter_lora` / `llama_rm_adapter_lora` /
  /// `llama_clear_adapter_lora` API with a single replace-all
  /// `llama_set_adapters_lora(ctx, adapters, n, scales)` call. We keep the
  /// active set here so the existing add/remove/clear public API can be
  /// preserved by re-applying the full batch whenever it changes.
  final Map<LoraAdapter, double> _activeLoras = {};

  /// Re-applies the full active adapter set to the context via the batch API.
  bool _applyLoras() {
    final n = _activeLoras.length;
    if (n == 0) {
      return Llama.lib.llama_set_adapters_lora(context, nullptr, 0, nullptr) ==
          0;
    }
    final adapters = malloc<Pointer<llama_adapter_lora>>(n);
    final scales = malloc<Float>(n);
    try {
      var i = 0;
      for (final entry in _activeLoras.entries) {
        adapters[i] = entry.key.nativePtr;
        scales[i] = entry.value;
        i++;
      }
      return Llama.lib.llama_set_adapters_lora(context, adapters, n, scales) == 0;
    } finally {
      malloc.free(adapters);
      malloc.free(scales);
    }
  }

  /// Applies [adapter] to this context with the given [scale] (0.0 to 1.0, default 1.0).
  ///
  /// Returns true on success. A scale of 0.0 effectively disables the adapter without removing it.
  bool setLora(LoraAdapter adapter, {double scale = 1.0}) {
    _activeLoras[adapter] = scale;
    return _applyLoras();
  }

  /// Removes [adapter] from this context. Does NOT free adapter memory — call [LoraAdapter.dispose].
  bool rmLora(LoraAdapter adapter) {
    _activeLoras.remove(adapter);
    return _applyLoras();
  }

  /// Removes all LoRA adapters from this context.
  void clearLoras() {
    _activeLoras.clear();
    Llama.lib.llama_set_adapters_lora(context, nullptr, 0, nullptr);
  }
}
