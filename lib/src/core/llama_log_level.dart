import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'llama_types.dart';
import 'llama_cpp.dart' show llama_cpp;

/// Log levels for controlling Dart-side and native llama.cpp output independently.
enum LlamaLogLevel {
  none(0),
  debug(1),
  info(2),
  warn(3),
  error(4);

  final int value;
  const LlamaLogLevel(this.value);
}

/// Manages independent log level control for Dart output and native llama.cpp output.
class LlamaLogger {
  static LlamaLogLevel _dartLevel = LlamaLogLevel.none;
  static LlamaLogLevel _nativeLevel = LlamaLogLevel.warn;

  static LlamaLogLevel get dartLevel => _dartLevel;
  static LlamaLogLevel get nativeLevel => _nativeLevel;

  /// Sets the Dart-side log level (controls print() calls inside the Dart bindings).
  static void setDartLogLevel(LlamaLogLevel level) {
    _dartLevel = level;
  }

  /// Sets the native llama.cpp / ggml log level. Messages below this level are
  /// suppressed via the native llama_log_set callback.
  /// [lib] must be the active [llama_cpp] instance (use [Llama.lib]).
  static void setNativeLogLevel(LlamaLogLevel level, llama_cpp lib) {
    _nativeLevel = level;
    _applyNativeCallback(lib);
  }

  /// Convenience: set both Dart and native levels to the same value.
  static void setLogLevel(LlamaLogLevel level, llama_cpp lib) {
    _dartLevel = level;
    _nativeLevel = level;
    _applyNativeCallback(lib);
  }

  static void _applyNativeCallback(llama_cpp lib) {
    if (_nativeLevel == LlamaLogLevel.none) {
      final nullPtr =
          Pointer.fromFunction<LlamaLogCallback>(_nativeCallbackNull);
      lib.llama_log_set(nullPtr, nullptr);
    } else {
      final filterPtr =
          Pointer.fromFunction<LlamaLogCallback>(_nativeCallbackFilter);
      lib.llama_log_set(filterPtr, nullptr);
    }
  }

  static void _nativeCallbackNull(
      int level, Pointer<Char> text, Pointer<Void> userData) {}

  static void _nativeCallbackFilter(
      int level, Pointer<Char> text, Pointer<Void> userData) {
    // ggml_log_level: DEBUG=1, INFO=2, WARN=3, ERROR=4
    if (level >= _nativeLevel.value) {
      final msg = text.cast<Utf8>().toDartString().trimRight();
      final prefix = switch (level) {
        1 => '[LLAMA DBG]',
        2 => '[LLAMA INF]',
        3 => '[LLAMA WRN]',
        4 => '[LLAMA ERR]',
        _ => '[LLAMA]',
      };
      print('$prefix $msg');
    }
  }

  /// Returns true if a Dart-side message at [level] should be emitted.
  static bool shouldLogDart(LlamaLogLevel level) =>
      level.index >= _dartLevel.index && _dartLevel != LlamaLogLevel.none;
}
