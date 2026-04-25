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

  /// Applies [adapter] to this context with the given [scale] (0.0 to 1.0, default 1.0).
  ///
  /// Returns true on success. A scale of 0.0 effectively disables the adapter without removing it.
  bool setLora(LoraAdapter adapter, {double scale = 1.0}) {
    final ret = Llama.lib.llama_set_adapter_lora(
        context, adapter.nativePtr, scale);
    return ret == 0;
  }

  /// Removes [adapter] from this context. Does NOT free adapter memory — call [LoraAdapter.dispose].
  bool rmLora(LoraAdapter adapter) {
    final ret =
        Llama.lib.llama_rm_adapter_lora(context, adapter.nativePtr);
    return ret == 0;
  }

  /// Removes all LoRA adapters from this context.
  void clearLoras() {
    Llama.lib.llama_clear_adapter_lora(context);
  }
}
