@Tags(['integration'])
library;

import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:llama_cpp_dart/src/core/llama_cpp.dart';
import 'package:llama_cpp_dart/src/core/service/sampler_factory.dart';

/// Integration tests for the per-prompt GBNF grammar override.
///
/// Prerequisites (macOS ARM64), same as `llama_integration_test.dart`:
///   - `test/fixtures/stories260K.gguf`
///   - `bin/MAC_ARM64/libllama.dylib`
///
/// Run:  flutter test --tags integration
void main() {
  final projectRoot = Directory.current.path;
  final modelPath = '$projectRoot/test/fixtures/stories260K.gguf';
  final libPath = '$projectRoot/bin/MAC_ARM64/libllama.dylib';

  final modelExists = File(modelPath).existsSync();
  final libExists = File(libPath).existsSync();

  if (!modelExists || !libExists) {
    test('SKIP: grammar integration tests require model + native lib',
        skip: true, () {
      if (!modelExists) fail('Missing: $modelPath');
      if (!libExists) fail('Missing: $libPath');
    });
    return;
  }

  setUpAll(() {
    Llama.libraryPath = libPath;
  });

  /// A grammar so tight that any unconstrained model fails it by accident.
  const yesNo = 'root ::= "yes" | "no"';

  Llama newLlama({bool greedy = true, String loadGrammar = ''}) => Llama(
        modelPath,
        contextParams: ContextParams()
          ..nCtx = 256
          ..nBatch = 256
          ..nPredict = 24,
        samplerParams: SamplerParams()
          ..temp = greedy ? 0.0 : 0.8
          ..seed = 1234
          ..greedy = greedy
          ..grammarStr = loadGrammar,
      );

  Future<String> generate(Llama llama, String prompt) async {
    llama.clear();
    llama.setPrompt(prompt);
    return (await llama.generateCompleteText(maxTokens: 12)).trim();
  }

  // ---------------------------------------------------------------------------
  // 1. Constrain, then revert — on one resident model, no reload.
  // ---------------------------------------------------------------------------
  group('Per-prompt grammar', () {
    late Llama llama;
    setUp(() => llama = newLlama());
    tearDown(() => llama.dispose());

    test('constrains generation, then reverts in the same session', () async {
      expect(llama.activeGrammar, isEmpty);

      expect(llama.applyGrammar(yesNo), isNull);
      expect(llama.activeGrammar, yesNo);
      final constrained = await generate(llama, 'Once upon a time');
      expect(constrained, anyOf('yes', 'no'),
          reason: 'grammar must admit nothing but the two permitted strings');

      // Revert: null means "back to the load-time grammar", which was empty.
      expect(llama.applyGrammar(null), isNull);
      expect(llama.activeGrammar, isEmpty);
      final free = await generate(llama, 'Once upon a time');
      expect(free, isNotEmpty);
      expect(free, isNot(anyOf('yes', 'no')),
          reason: 'unconstrained generation must be ordinary prose again');
      expect(free.length, greaterThan(5));
    });

    test('empty string explicitly drops the grammar', () async {
      llama.applyGrammar(yesNo);
      expect(llama.activeGrammar, yesNo);
      expect(llama.applyGrammar(''), isNull);
      expect(llama.activeGrammar, isEmpty);
      final free = await generate(llama, 'Once upon a time');
      expect(free, isNot(anyOf('yes', 'no')));
    });

    // -------------------------------------------------------------------------
    // 2. Identical grammar → no rebuild, and still constrained.
    // -------------------------------------------------------------------------
    test('the same grammar twice does not rebuild the sampler', () async {
      expect(llama.samplerRebuildCount, 0);

      expect(llama.applyGrammar(yesNo), isNull);
      expect(llama.samplerRebuildCount, 1);
      final first = await generate(llama, 'Once upon a time');
      expect(first, anyOf('yes', 'no'));

      // Same grammar string — must be a no-op...
      expect(llama.applyGrammar(yesNo), isNull);
      expect(llama.samplerRebuildCount, 1,
          reason: 'an identical grammar must not cost a rebuild');
      // ...and an omitted root must normalise to the same thing.
      expect(llama.applyGrammar(yesNo, grammarRoot: 'root'), isNull);
      expect(llama.samplerRebuildCount, 1);

      // ...but the reused stateful grammar sampler must still have been reset,
      // otherwise it resumes in its terminal state and masks every token.
      final second = await generate(llama, 'Once upon a time');
      expect(second, anyOf('yes', 'no'),
          reason: 'grammar state must be reset between generations');
    });

    test('consecutive grammar-less prompts never rebuild', () async {
      expect(llama.applyGrammar(null), isNull);
      expect(llama.applyGrammar(null), isNull);
      expect(llama.applyGrammar(null), isNull);
      expect(llama.samplerRebuildCount, 0);
      final text = await generate(llama, 'Once upon a time');
      expect(text, isNotEmpty);
    });

    // -------------------------------------------------------------------------
    // 3. Bad GBNF degrades to unconstrained, with a notice.
    // -------------------------------------------------------------------------
    test('invalid GBNF degrades to unconstrained generation', () async {
      final notice = llama.applyGrammar('this is not grammar {{{');
      expect(notice, isNotNull);
      expect(notice, contains('unconstrained'));
      expect(llama.activeGrammar, isEmpty,
          reason: 'a grammar that failed to compile is not active');

      final text = await generate(llama, 'Once upon a time');
      expect(text, isNotEmpty,
          reason: 'a bad grammar must never wedge generation');
      expect(text.length, greaterThan(5));
    });

    test('a grammar naming a missing root rule degrades too', () async {
      final notice = llama.applyGrammar(yesNo, grammarRoot: 'nosuchrule');
      expect(notice, isNotNull);
      expect(llama.activeGrammar, isEmpty);
      expect(await generate(llama, 'Once upon a time'), isNotEmpty);
    });

    test('a still-usable model survives a bad grammar and takes a good one',
        () async {
      expect(llama.applyGrammar('}}} nonsense'), isNotNull);
      expect(llama.applyGrammar(yesNo), isNull);
      expect(await generate(llama, 'Once upon a time'), anyOf('yes', 'no'));
    });
  });

  // ---------------------------------------------------------------------------
  // 4. Greedy sampling must still be constrainable.
  // ---------------------------------------------------------------------------
  group('Grammar under greedy sampling', () {
    test('greedy generation is constrained by a per-prompt grammar', () async {
      final llama = newLlama(greedy: true);
      addTearDown(llama.dispose);
      expect(llama.applyGrammar(yesNo), isNull);
      expect(await generate(llama, 'Once upon a time'), anyOf('yes', 'no'));
    });

    test('non-greedy generation is constrained too', () async {
      final llama = newLlama(greedy: false);
      addTearDown(llama.dispose);
      expect(llama.applyGrammar(yesNo), isNull);
      expect(await generate(llama, 'Once upon a time'), anyOf('yes', 'no'));
    });

    test('a load-time grammar survives a null per-prompt grammar', () async {
      final llama = newLlama(greedy: true, loadGrammar: yesNo);
      addTearDown(llama.dispose);
      expect(llama.activeGrammar, yesNo);
      expect(llama.applyGrammar(null), isNull);
      expect(llama.samplerRebuildCount, 0,
          reason: 'null must not disturb a load-time grammar');
      expect(await generate(llama, 'Once upon a time'), anyOf('yes', 'no'));
    });
  });

  // ---------------------------------------------------------------------------
  // End-to-end through the isolate: LlamaParent.sendPrompt(grammarStr: ...).
  // This is the path the consuming app takes — the model stays resident and
  // only the grammar changes between prompts.
  // ---------------------------------------------------------------------------
  group('LlamaParent per-prompt grammar', () {
    late LlamaParent parent;

    setUp(() async {
      parent = LlamaParent(LlamaLoad(
        path: modelPath,
        modelParams: ModelParams(),
        contextParams: ContextParams()
          ..nCtx = 256
          ..nBatch = 256
          ..nPredict = 24,
        samplingParams: SamplerParams()
          ..temp = 0.0
          ..seed = 1234
          ..greedy = true,
      ));
      await parent.init();
    });

    tearDown(() async {
      await parent.dispose();
    });

    /// Sends one prompt and returns (text, completion event).
    Future<(String, CompletionEvent)> run(String prompt,
        {String? grammarStr}) async {
      final buffer = StringBuffer();
      final sub = parent.stream.listen(buffer.write);
      final id = await parent.sendPrompt(prompt, grammarStr: grammarStr);
      final event = await parent.completions
          .firstWhere((e) => e.promptId == id)
          .timeout(const Duration(seconds: 30));
      await sub.cancel();
      await parent.clear();
      return (buffer.toString().trim(), event);
    }

    test('a grammar rides the prompt, and the next prompt is free again',
        () async {
      final (constrained, ok) =
          await run('Once upon a time', grammarStr: yesNo);
      expect(ok.success, isTrue);
      expect(ok.errorDetails, isNull);
      expect(constrained, anyOf('yes', 'no'));

      final (free, ok2) = await run('Once upon a time');
      expect(ok2.success, isTrue);
      expect(free, isNotEmpty);
      expect(free, isNot(anyOf('yes', 'no')));
    });

    test('a bad grammar is a non-fatal notice, not a failed generation',
        () async {
      final (text, event) =
          await run('Once upon a time', grammarStr: 'not gbnf {{{');
      expect(event.success, isTrue,
          reason: 'a bad grammar degrades; it does not fail the prompt');
      expect(event.errorDetails, isNotNull);
      expect(event.errorDetails, contains('unconstrained'));
      expect(text, isNotEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // SamplerFactory chain composition (the greedy restructure).
  // ---------------------------------------------------------------------------
  group('SamplerFactory chain composition', () {
    late Llama llama;
    late llama_cpp lib;
    setUp(() {
      llama = newLlama();
      lib = Llama.lib;
    });
    tearDown(() => llama.dispose());

    List<String> chainOf(SamplerParams params, {void Function(String)? onErr}) {
      final smpl = SamplerFactory.build(
        lib: lib,
        vocab: llama.vocab,
        model: llama.model,
        params: params,
        onGrammarError: onErr,
      );
      try {
        return [
          for (var i = 0; i < lib.llama_sampler_chain_n(smpl); i++)
            lib
                .llama_sampler_name(lib.llama_sampler_chain_get(smpl, i))
                .cast<Utf8>()
                .toDartString(),
        ];
      } finally {
        lib.llama_sampler_free(smpl);
      }
    }

    test('greedy without a grammar is unchanged: greedy alone', () {
      expect(chainOf(SamplerParams()..greedy = true), ['greedy']);
    });

    test('greedy with a grammar puts the grammar first, then greedy', () {
      expect(
        chainOf(SamplerParams()
          ..greedy = true
          ..grammarStr = yesNo),
        ['grammar', 'greedy'],
      );
    });

    test('non-greedy without a grammar has no grammar sampler', () {
      final chain = chainOf(SamplerParams());
      expect(chain, isNot(contains('grammar')));
      // llama.cpp prefixes a no-op sampler's name with '?', so match loosely.
      expect(chain.first, contains('penalties'));
      expect(chain.last, 'dist');
    });

    test('non-greedy with a grammar puts the grammar before every selector',
        () {
      final chain = chainOf(SamplerParams()..grammarStr = yesNo);
      expect(chain.first, 'grammar');
      expect(chain.last, 'dist');
      expect(chain.indexOf('grammar'), lessThan(chain.indexOf('dist')));
    });

    test('an omitted root falls back to the conventional root rule', () {
      expect(kDefaultGrammarRoot, 'root');
      expect(
        chainOf(SamplerParams()
          ..greedy = true
          ..grammarStr = yesNo
          ..grammarRoot = ''),
        ['grammar', 'greedy'],
      );
    });

    test('a bad grammar yields a complete chain minus the grammar', () {
      String? err;
      final chain = chainOf(
        SamplerParams()
          ..greedy = true
          ..grammarStr = 'not gbnf {{{',
        onErr: (m) => err = m,
      );
      expect(err, isNotNull);
      expect(chain, ['greedy'],
          reason: 'never a half-built chain — just the ungrammared one');
    });
  });
}
