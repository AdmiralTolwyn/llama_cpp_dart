import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../llama_cpp.dart';
import '../sampler_params.dart';

/// GBNF root rule used when a caller supplies a grammar but does not name its
/// root. llama.cpp requires an explicit root rule name, and effectively every
/// GBNF in the wild calls it `root`.
const String kDefaultGrammarRoot = 'root';

class SamplerFactory {
  /// Builds a sampler chain from [params].
  ///
  /// [onGrammarError] is invoked (once, non-fatally) when `params.grammarStr`
  /// is non-empty but llama.cpp refuses to compile it. The returned chain is
  /// then a complete, valid, *unconstrained* chain — never a half-built one.
  static Pointer<llama_sampler> build({
    required llama_cpp lib,
    required Pointer<llama_vocab> vocab,
    required Pointer<llama_model> model,
    required SamplerParams params,
    void Function(String message)? onGrammarError,
  }) {
    final sparams = lib.llama_sampler_chain_default_params();
    sparams.no_perf = false;
    final smpl = lib.llama_sampler_chain_init(sparams);

    // The grammar sampler goes FIRST, before any selection sampler. It masks
    // grammar-illegal tokens to -INF, so whatever picks the token afterwards —
    // the greedy argmax below, or the dist sampler at the end of the full
    // chain — only ever sees legal candidates. Adding it after the selection
    // sampler would constrain nothing: the token would already be chosen.
    //
    // This is also why the greedy early-return below no longer skips the
    // grammar: `greedy` describes *how* a token is picked, not *which* tokens
    // are admissible. A tuned, near-greedy model must still be constrainable.
    _addGrammar(
      lib: lib,
      vocab: vocab,
      smpl: smpl,
      params: params,
      onGrammarError: onGrammarError,
    );

    if (params.greedy) {
      lib.llama_sampler_chain_add(smpl, lib.llama_sampler_init_greedy());
      return smpl;
    }

    lib.llama_sampler_chain_add(
      smpl,
      lib.llama_sampler_init_penalties(
        params.penaltyLastTokens,
        params.penaltyRepeat,
        params.penaltyFreq,
        params.penaltyPresent,
      ),
    );

    if (params.dryMultiplier > 0.0) {
      try {
        final breakers = params.dryBreakers;
        final breakerCount = breakers.length;

        final breakersPtr = malloc<Pointer<Char>>(breakerCount);
        final allocatedStrings = <Pointer<Char>>[];

        for (int i = 0; i < breakerCount; i++) {
          final strPtr = breakers[i].toNativeUtf8().cast<Char>();
          breakersPtr[i] = strPtr;
          allocatedStrings.add(strPtr);
        }

        final int nCtxTrain = lib.llama_model_n_ctx_train(model);

        lib.llama_sampler_chain_add(
          smpl,
          lib.llama_sampler_init_dry(
            vocab,
            nCtxTrain,
            params.dryMultiplier,
            params.dryBase,
            params.dryAllowedLen,
            params.dryPenaltyLastN,
            breakersPtr,
            breakerCount,
          ),
        );

        for (var ptr in allocatedStrings) {
          malloc.free(ptr);
        }
        malloc.free(breakersPtr);
      } catch (_) {}
    }

    if (params.mirostat == 2) {
      lib.llama_sampler_chain_add(
          smpl,
          lib.llama_sampler_init_mirostat_v2(
              params.seed, params.mirostatTau, params.mirostatEta));
    } else if (params.mirostat == 1) {
      lib.llama_sampler_chain_add(
          smpl,
          lib.llama_sampler_init_mirostat(
              lib.llama_n_vocab(vocab),
              params.seed,
              params.mirostatTau,
              params.mirostatEta,
              params.mirostatM));
    } else {
      lib.llama_sampler_chain_add(
          smpl, lib.llama_sampler_init_top_k(params.topK));

      lib.llama_sampler_chain_add(
          smpl, lib.llama_sampler_init_top_p(params.topP, 1));

      lib.llama_sampler_chain_add(
          smpl, lib.llama_sampler_init_min_p(params.minP, 1));

      lib.llama_sampler_chain_add(
          smpl, lib.llama_sampler_init_typical(params.typical, 1));

      if (params.dynatempRange > 0.0) {
        try {
          lib.llama_sampler_chain_add(
              smpl,
              lib.llama_sampler_init_temp_ext(
                  params.temp, params.dynatempRange, params.dynatempExponent));
        } catch (_) {
          lib.llama_sampler_chain_add(
              smpl, lib.llama_sampler_init_temp(params.temp));
        }
      } else {
        lib.llama_sampler_chain_add(
            smpl, lib.llama_sampler_init_temp(params.temp));
      }

      if (params.xtcProbability > 0.0) {
        try {
          lib.llama_sampler_chain_add(
              smpl,
              lib.llama_sampler_init_xtc(params.xtcProbability,
                  params.xtcThreshold, 1, params.seed));
        } catch (_) {}
      }
    }

    lib.llama_sampler_chain_add(
        smpl, lib.llama_sampler_init_dist(params.seed));

    return smpl;
  }

  /// Appends a grammar sampler to [smpl] when [params] carries one.
  ///
  /// Returns true when a grammar sampler was actually installed. A grammar
  /// that llama.cpp cannot compile (`llama_sampler_init_grammar` returns
  /// nullptr on invalid GBNF or an unknown root rule) is reported through
  /// [onGrammarError] and skipped, leaving the rest of the chain intact.
  static bool _addGrammar({
    required llama_cpp lib,
    required Pointer<llama_vocab> vocab,
    required Pointer<llama_sampler> smpl,
    required SamplerParams params,
    void Function(String message)? onGrammarError,
  }) {
    if (params.grammarStr.isEmpty) return false;

    final root =
        params.grammarRoot.isEmpty ? kDefaultGrammarRoot : params.grammarRoot;
    final grammarStrPtr = params.grammarStr.toNativeUtf8().cast<Char>();
    final grammarRootPtr = root.toNativeUtf8().cast<Char>();
    try {
      final grammar =
          lib.llama_sampler_init_grammar(vocab, grammarStrPtr, grammarRootPtr);
      if (grammar == nullptr) {
        onGrammarError?.call(
            'Grammar rejected by llama.cpp (invalid GBNF, or no rule named '
            '"$root"); generation continues unconstrained');
        return false;
      }
      lib.llama_sampler_chain_add(smpl, grammar);
      return true;
    } catch (e) {
      onGrammarError?.call(
          'Grammar compilation threw ($e); generation continues unconstrained');
      return false;
    } finally {
      malloc.free(grammarStrPtr);
      malloc.free(grammarRootPtr);
    }
  }
}
