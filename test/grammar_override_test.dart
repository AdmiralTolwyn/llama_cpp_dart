import 'package:flutter_test/flutter_test.dart';
import 'package:llama_cpp_dart/src/core/sampler_params.dart';
import 'package:llama_cpp_dart/src/isolate/isolate_types.dart';

void main() {
  group('SamplerParams.copy', () {
    test('reproduces every field', () {
      final original = SamplerParams()
        ..temp = 0.3
        ..dynatempRange = 0.2
        ..dynatempExponent = 1.5
        ..topK = 7
        ..topP = 0.6
        ..minP = 0.02
        ..typical = 0.9
        ..topNSigma = 2.0
        ..xtcProbability = 0.4
        ..xtcThreshold = 0.3
        ..mirostat = 2
        ..mirostatTau = 4.0
        ..mirostatEta = 0.2
        ..mirostatM = 50
        ..penaltyLastTokens = 32
        ..penaltyRepeat = 1.1
        ..penaltyFreq = 0.5
        ..penaltyPresent = 0.4
        ..penaltyNewline = true
        ..ignoreEOS = true
        ..dryMultiplier = 0.8
        ..dryBase = 1.2
        ..dryAllowedLen = 3
        ..dryPenaltyLastN = 128
        ..dryBreakers = ['a', 'b']
        ..grammarStr = 'root ::= "x"'
        ..grammarRoot = 'root'
        ..greedy = true
        ..softmax = false
        ..seed = 42
        ..topPKeep = 3
        ..minPKeep = 4
        ..typicalKeep = 5
        ..xtcKeep = 6
        ..xtcLength = 7;

      final copy = original.copy();

      expect(copy.temp, 0.3);
      expect(copy.dynatempRange, 0.2);
      expect(copy.dynatempExponent, 1.5);
      expect(copy.topK, 7);
      expect(copy.topP, 0.6);
      expect(copy.minP, 0.02);
      expect(copy.typical, 0.9);
      expect(copy.topNSigma, 2.0);
      expect(copy.xtcProbability, 0.4);
      expect(copy.xtcThreshold, 0.3);
      expect(copy.mirostat, 2);
      expect(copy.mirostatTau, 4.0);
      expect(copy.mirostatEta, 0.2);
      expect(copy.mirostatM, 50);
      expect(copy.penaltyLastTokens, 32);
      expect(copy.penaltyRepeat, 1.1);
      expect(copy.penaltyFreq, 0.5);
      expect(copy.penaltyPresent, 0.4);
      expect(copy.penaltyNewline, true);
      expect(copy.ignoreEOS, true);
      expect(copy.dryMultiplier, 0.8);
      expect(copy.dryBase, 1.2);
      expect(copy.dryAllowedLen, 3);
      expect(copy.dryPenaltyLastN, 128);
      expect(copy.dryBreakers, ['a', 'b']);
      expect(copy.grammarStr, 'root ::= "x"');
      expect(copy.grammarRoot, 'root');
      expect(copy.greedy, true);
      expect(copy.softmax, false);
      expect(copy.seed, 42);
      expect(copy.topPKeep, 3);
      expect(copy.minPKeep, 4);
      expect(copy.typicalKeep, 5);
      expect(copy.xtcKeep, 6);
      expect(copy.xtcLength, 7);
    });

    test('is independent of the original', () {
      final original = SamplerParams()
        ..grammarStr = 'root ::= "x"'
        ..dryBreakers = ['a'];
      final copy = original.copy()
        ..grammarStr = 'root ::= "y"'
        ..dryBreakers.add('b');

      expect(original.grammarStr, 'root ::= "x"');
      expect(original.dryBreakers, ['a'],
          reason: 'dryBreakers must be deep-copied, not aliased');
      expect(copy.grammarStr, 'root ::= "y"');
    });
  });

  group('LlamaPrompt grammar fields', () {
    test('default to null (previous behaviour)', () {
      final p = LlamaPrompt('hello', 'id-1');
      expect(p.grammarStr, isNull);
      expect(p.grammarRoot, isNull);
    });

    test('carry the per-prompt grammar verbatim', () {
      final p = LlamaPrompt('hello', 'id-1',
          slotId: 'scope_1',
          grammarStr: 'root ::= "yes" | "no"',
          grammarRoot: 'root');
      expect(p.grammarStr, 'root ::= "yes" | "no"');
      expect(p.grammarRoot, 'root');
      expect(p.slotId, 'scope_1');
    });
  });
}
