import 'dart:async';

/// A function that generates text from a prompt.
typedef GenerateFunction = Future<String?> Function(String prompt);

/// A pending parallel completion request.
class ParallelRequest {
  final String id;
  final String prompt;
  final Completer<String?> _completer = Completer<String?>();
  final void Function(String token)? onToken;
  final StringBuffer _buffer = StringBuffer();
  bool _cancelled = false;

  ParallelRequest({
    required this.id,
    required this.prompt,
    this.onToken,
  });

  Future<String?> get future => _completer.future;
  bool get isCancelled => _cancelled;

  void addToken(String token) {
    if (_cancelled) return;
    _buffer.write(token);
    onToken?.call(token);
  }

  void complete() {
    if (!_completer.isCompleted) {
      _completer.complete(_buffer.toString());
    }
  }

  void cancel() {
    _cancelled = true;
    if (!_completer.isCompleted) {
      _completer.complete(_buffer.toString());
    }
  }

  void fail(String error) {
    if (!_completer.isCompleted) {
      _completer.complete(null);
    }
  }
}

/// Manages slot-based parallel request processing for concurrent
/// completion requests.
///
/// Mirrors llama.rn's `context.parallel` API:
/// - `enable(nParallel)` — configure slot count
/// - `completion(params, onToken)` — queue a request
/// - `disable()` — teardown
///
/// Since llama_cpp_dart uses an isolate-based architecture, true parallel
/// decoding requires native-level changes. This wrapper provides a
/// sequential queue that processes requests one at a time but provides
/// the same API surface for future native parallel support.
class ParallelDecoder {
  final GenerateFunction _generate;
  int _nParallel;
  bool _enabled = false;
  final _queue = <ParallelRequest>[];
  bool _processing = false;

  ParallelDecoder({
    required GenerateFunction generate,
    int nParallel = 2,
  })  : _generate = generate,
        _nParallel = nParallel;

  bool get isEnabled => _enabled;
  int get slotCount => _nParallel;
  int get queueLength => _queue.length;

  /// Enable parallel mode with N slots.
  void enable({int nParallel = 2}) {
    _nParallel = nParallel;
    _enabled = true;
  }

  /// Disable parallel mode and cancel pending requests.
  void disable() {
    _enabled = false;
    for (final req in _queue) {
      req.cancel();
    }
    _queue.clear();
  }

  /// Queue a completion request. Returns a handle with the future result
  /// and a cancel function.
  ({String requestId, Future<String?> promise, void Function() stop})
      completion(String prompt, {void Function(String token)? onToken}) {
    final id = 'par_${DateTime.now().millisecondsSinceEpoch}';
    final request = ParallelRequest(
      id: id,
      prompt: prompt,
      onToken: onToken,
    );
    _queue.add(request);
    _processQueue();

    return (
      requestId: id,
      promise: request.future,
      stop: () => request.cancel(),
    );
  }

  Future<void> _processQueue() async {
    if (_processing) return;
    _processing = true;

    while (_queue.isNotEmpty) {
      final request = _queue.removeAt(0);
      if (request.isCancelled) continue;

      try {
        final result = await _generate(request.prompt);
        if (result != null) {
          request.addToken(result);
        }
        request.complete();
      } catch (e) {
        request.fail('$e');
      }
    }

    _processing = false;
  }
}
