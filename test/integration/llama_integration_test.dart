@Tags(['integration'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

/// Integration tests that load a real GGUF model and exercise the native FFI
/// bindings.
///
/// Prerequisites (macOS ARM64):
///   - `test/fixtures/stories260K.gguf`  (1.2 MB, auto-downloaded)
///   - `bin/MAC_ARM64/libllama.dylib`    (pre-built native library)
///
/// Run:  flutter test --tags integration
/// Skip: flutter test --exclude-tags integration  (default in CI)
void main() {
  final projectRoot = Directory.current.path;
  final modelPath = '$projectRoot/test/fixtures/stories260K.gguf';
  final libPath = '$projectRoot/bin/MAC_ARM64/libllama.dylib';

  final modelExists = File(modelPath).existsSync();
  final libExists = File(libPath).existsSync();

  if (!modelExists || !libExists) {
    test('SKIP: integration tests require model + native lib', skip: true, () {
      if (!modelExists) fail('Missing: $modelPath');
      if (!libExists) fail('Missing: $libPath');
    });
    return;
  }

  setUpAll(() {
    Llama.libraryPath = libPath;
  });

  // ---------------------------------------------------------------------------
  // Model loading & diagnostics
  // ---------------------------------------------------------------------------
  group('Model loading', () {
    late Llama llama;

    setUp(() {
      llama = Llama(
        modelPath,
        contextParams: ContextParams()
          ..nCtx = 256
          ..nBatch = 256
          ..nPredict = 64,
        samplerParams: SamplerParams()
          ..temp = 0.0
          ..greedy = true,
      );
    });

    tearDown(() => llama.dispose());

    test('model loads and reports ready status', () {
      expect(llama.status, LlamaStatus.ready);
      expect(llama.isDisposed, false);
    });

    test('diagnostics return valid model info', () {
      final diag = llama.getDiagnostics();
      expect(diag.modelDesc, isNotEmpty);
      expect(diag.nParams, greaterThan(0));
      expect(diag.nVocab, greaterThan(0));
      expect(diag.nCtx, 256);
      expect(diag.modelSizeBytes, greaterThan(0));
    });
  });

  // ---------------------------------------------------------------------------
  // Tokenization
  // ---------------------------------------------------------------------------
  group('Tokenization', () {
    late Llama llama;

    setUp(() {
      llama = Llama(
        modelPath,
        contextParams: ContextParams()
          ..nCtx = 256
          ..nBatch = 256,
      );
    });

    tearDown(() => llama.dispose());

    test('tokenize returns non-empty token list', () {
      final tokens = llama.tokenize('Hello world', true);
      expect(tokens, isNotEmpty);
      expect(tokens.length, greaterThanOrEqualTo(2));
    });

    test('addBos=true prepends one extra token', () {
      final withBos = llama.tokenize('test', true);
      final withoutBos = llama.tokenize('test', false);
      expect(withBos.length, withoutBos.length + 1);
    });

    test('tokenize throws on empty text', () {
      expect(() => llama.tokenize('', true), throwsA(isA<ArgumentError>()));
    });
  });

  // ---------------------------------------------------------------------------
  // Text generation
  // ---------------------------------------------------------------------------
  group('Text generation', () {
    late Llama llama;

    setUp(() {
      llama = Llama(
        modelPath,
        contextParams: ContextParams()
          ..nCtx = 256
          ..nBatch = 256
          ..nPredict = 32,
        samplerParams: SamplerParams()
          ..temp = 0.0
          ..greedy = true,
      );
    });

    tearDown(() => llama.dispose());

    test('streaming generation produces tokens', () async {
      llama.setPrompt('Once upon a time');
      final tokens = <String>[];
      await for (final token in llama.generateText()) {
        tokens.add(token);
        if (tokens.length >= 10) break;
      }
      expect(tokens, isNotEmpty);
      expect(tokens.join(), isNotEmpty);
    });

    test('generateCompleteText returns non-empty string', () async {
      llama.setPrompt('Once upon a time');
      final result = await llama.generateCompleteText(maxTokens: 16);
      expect(result, isNotEmpty);
      expect(result.length, greaterThan(2));
    });

    test('clear resets context for re-prompting', () async {
      llama.setPrompt('Hello');
      final first = await llama.generateCompleteText(maxTokens: 8);
      expect(first, isNotEmpty);

      llama.clear();

      llama.setPrompt('Hello');
      final second = await llama.generateCompleteText(maxTokens: 8);
      expect(second, isNotEmpty);

      // Greedy sampling → same prompt should produce identical output.
      expect(second, first);
    });

    test('context space decreases after generation', () async {
      final before = llama.getRemainingContextSpace();
      llama.setPrompt('Once upon a time');
      await llama.generateCompleteText(maxTokens: 8);
      final after = llama.getRemainingContextSpace();
      expect(after, lessThan(before));
    });
  });

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------
  group('Lifecycle', () {
    test('dispose prevents further operations', () {
      final llama = Llama(
        modelPath,
        contextParams: ContextParams()
          ..nCtx = 128
          ..nBatch = 128,
      );
      llama.dispose();
      expect(llama.status, LlamaStatus.disposed);
      expect(llama.isDisposed, true);
      expect(() => llama.clear(), throwsA(isA<StateError>()));
    });

    test('double dispose is safe', () {
      final llama = Llama(
        modelPath,
        contextParams: ContextParams()
          ..nCtx = 128
          ..nBatch = 128,
      );
      llama.dispose();
      llama.dispose(); // must not throw
      expect(llama.isDisposed, true);
    });
  });

  // ---------------------------------------------------------------------------
  // Isolate round-trip (LlamaParent.countTokens, v0.3.11)
  //
  // IMPORTANT: no synchronous Llama may be constructed while the LlamaParent
  // child is alive. llama_log_set is process-global and Pointer.fromFunction
  // callbacks are isolate-bound — a sync Llama in the main isolate re-registers
  // the callback, and the next child-side log then aborts the VM with
  // "Cannot invoke native callback from a different isolate". The reference
  // count is therefore computed in setUpAll, before the child spawns.
  // ---------------------------------------------------------------------------
  group('LlamaParent.countTokens', () {
    late int directHelloCount;
    late LlamaParent parent;

    setUpAll(() async {
      final llama = Llama(
        modelPath,
        contextParams: ContextParams()
          ..nCtx = 256
          ..nBatch = 256,
      );
      directHelloCount = llama.tokenize('Hello world', true).length;
      llama.dispose();

      parent = LlamaParent(LlamaLoad(
        path: modelPath,
        modelParams: ModelParams(),
        contextParams: ContextParams()
          ..nCtx = 256
          ..nBatch = 256,
        samplingParams: SamplerParams(),
      ));
      await parent.init();
    });

    tearDownAll(() => parent.dispose());

    test('matches the synchronous tokenizer count', () async {
      final viaIsolate = await parent.countTokens('Hello world', addBos: true);
      expect(viaIsolate, directHelloCount);
      expect(viaIsolate, greaterThanOrEqualTo(2));
    });

    test('addBos=false yields one fewer token', () async {
      final withBos = await parent.countTokens('test', addBos: true);
      final withoutBos = await parent.countTokens('test', addBos: false);
      expect(withBos, withoutBos + 1);
    });

    test('sequential counts do not interfere', () async {
      final a = await parent.countTokens('one two three four five');
      final b = await parent.countTokens('one');
      expect(a, greaterThan(b));
    });
  });

  // ---------------------------------------------------------------------------
  // Supersede semantics (Crashlytics: fatal 'Bad state: Operation superseded
  // by: context clear'). A newer operation (e.g. clear()) issued while a
  // previous _sendCommand-based op (load / stop / clear) is still pending
  // supersedes it. A LIVE awaiter must receive LlamaSupersededException; a
  // DETACHED / fire-and-forget awaiter must NOT leak an unhandled async error.
  // ---------------------------------------------------------------------------
  group('supersede', () {
    late LlamaParent parent;

    setUp(() async {
      parent = LlamaParent(LlamaLoad(
        path: modelPath,
        modelParams: ModelParams(),
        contextParams: ContextParams()
          ..nCtx = 256
          ..nBatch = 256,
        samplingParams: SamplerParams(),
      ));
      await parent.init();
    });

    tearDown(() => parent.dispose());

    test('live awaiter of a superseded op receives LlamaSupersededException',
        () async {
      // Two clears in the same turn: the second supersedes the first before the
      // child confirms it. The first clear's awaiter is live (we await it).
      final first = parent.clear();
      final second = parent.clear();
      await expectLater(first, throwsA(isA<LlamaSupersededException>()));
      // The superseding op still completes normally.
      await second;
    });

    test('superseded exception preserves the legacy message text', () async {
      final first = parent.clear();
      final second = parent.clear();
      try {
        await first;
        fail('expected supersede');
      } catch (e) {
        expect(e, isA<LlamaSupersededException>());
        expect(e.toString(), contains('Operation superseded'));
        expect(e.toString(), contains('context clear'));
      }
      await second;
    });

    test('a superseded op handled with catchError leaks nothing to the zone '
        '(app-side cancellation contract)', () async {
      // The error of a superseded op propagates to its awaiter via the live
      // .timeout listener — the fork cannot suppress that for the awaiter, so
      // fire-and-forget callers MUST attach a catch. This asserts that the
      // documented app-side pattern (catchError swallowing the supersede)
      // leaves NO unhandled async error in the zone, which is what stops the
      // Crashlytics fatal.
      final unhandled = <Object>[];
      LlamaSupersededException? caught;
      await runZonedGuarded(() async {
        // Fire-and-forget, but with the app-side benign-cancellation catch.
        // ignore: unawaited_futures
        parent.clear().catchError((Object e) {
          if (e is LlamaSupersededException) {
            caught = e;
            return; // benign cancellation
          }
          throw e; // anything else stays fatal
        });
        // Supersede in the same turn (child cannot have confirmed yet), so the
        // first clear is guaranteed to be superseded, not confirmed.
        final superseding = parent.clear();
        await Future.delayed(const Duration(milliseconds: 100));
        await superseding;
      }, (e, s) => unhandled.add(e));
      expect(caught, isA<LlamaSupersededException>());
      expect(unhandled, isEmpty,
          reason: 'benign-cancellation catch still leaked: $unhandled');
    });
  });
}
