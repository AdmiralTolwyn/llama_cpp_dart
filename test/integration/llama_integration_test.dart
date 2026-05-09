@Tags(['integration'])
library;

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
}
