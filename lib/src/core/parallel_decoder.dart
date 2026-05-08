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
      _completer.completeError(error);
    }
  }
}

/// Sequential request queue with the surface of llama.rn's `parallel` API.
///
/// **NOT actually parallel.** Despite the name and the `nParallel` parameter,
/// this implementation processes requests one at a time via the supplied
/// [GenerateFunction]. Requests block each other. The `nParallel` value is
/// accepted for API compatibility with llama.rn but is not honoured today.
///
/// True parallel decoding requires native-level seq_id slot scheduling, which
/// lives in [LlamaService] (different code path). This wrapper exists so code
/// written against llama.rn's `enable`/`completion`/`disable` shape can run
/// against this binding without modification.
///
/// If you need actual concurrency, use [LlamaService] directly with
/// per-session seq_ids and the round-robin scheduler.
class ParallelDecoder {
  final GenerateFunction _generate;
  // ignore: unused_field
  int _nParallel; // accepted for API compatibility; ignored by _processQueue.
  bool _enabled = false;
  final _queue = <ParallelRequest>[];
  bool _processing = false;

  ParallelDecoder({
    required GenerateFunction generate,
    int nParallel = 2,
  })  : _generate = generate,
        _nParallel = nParallel;

  bool get isEnabled => _enabled;
  /// Configured slot count. **Not honoured** — see class docs.
  int get slotCount => _nParallel;
  int get queueLength => _queue.length;

  /// Enable the queue. The `nParallel` argument is accepted for API parity
  /// with llama.rn but is ignored — see class docs.
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
