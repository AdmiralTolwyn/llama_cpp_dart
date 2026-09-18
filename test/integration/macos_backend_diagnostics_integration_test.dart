@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

/// Regression test for the diagnostics backend-name bug measured on this
/// Mac: `Llama.getBackendName()` reported "CPU" while a headless run's
/// native log showed `ggml_metal_device_init: GPU name: MTL0 (Apple M5
/// Max)` and `load_tensors: offloaded 35/35 layers to GPU`.
///
/// Root cause (see `lib/src/core/llama_diagnostics.dart`): the old
/// `_resolveBackendName` substring-matched `llama_print_system_info()`'s
/// text for "METAL = 1", but this engine line's Metal backend registers
/// as "MTL" (`MTL : EMBED_LIBRARY = 1`), so the match never hit and every
/// GPU run silently fell through to "CPU". The fix asks the live
/// ggml-backend device registry (`ggml_backend_dev_count/get/type/
/// backend_reg`, `ggml_backend_reg_name` — all already bound in
/// `llama_cpp.dart`) instead of parsing that string.
///
/// Prerequisites (this Mac only, Apple Silicon):
///   - The unsigned macOS Release framework binary built in the w5
///     diagnostics run: see `libPath` below (verified sha256 before use).
///   - The real distill model: see `modelPath` below (read-only).
///
/// Run:  flutter test --tags integration test/integration/macos_backend_diagnostics_integration_test.dart
void main() {
  const libPath =
      '/private/tmp/bagel-w5-unsigned-dd/Build/Products/Release/bagel_commander_mobile.app/Contents/Frameworks/Llama.framework/Versions/A/Llama';
  const modelPath =
      '/Users/antonromanyuk/Documents/Git/bagel_models/bagel-distill-4b-i1400-Q4_K_M.gguf';
  // Pins the exact binary this test was measured against — the whole
  // point of the regression is a byte-level engine behaviour, not just
  // "some framework at this path".
  const expectedLibSha256 =
      '66fcb196680dc888d40f98d484835203270105b9e89f66411a731a78f4406276';

  final libFile = File(libPath);
  final modelFile = File(modelPath);
  final libExists = libFile.existsSync();
  final modelExists = modelFile.existsSync();
  // Shell out to `shasum` (present on every Mac) rather than pulling in
  // package:crypto as a new dependency just for a one-off pin check.
  final libShaMatches = libExists &&
      Process.runSync('shasum', ['-a', '256', libPath])
          .stdout
          .toString()
          .trim()
          .startsWith(expectedLibSha256);

  if (!libExists || !modelExists || !libShaMatches) {
    test(
        'SKIP: macOS backend-diagnostics regression needs the pinned w5 '
        'framework binary + the real distill model on this Mac',
        skip: true, () {
      if (!libExists) fail('Missing: $libPath');
      if (!modelExists) fail('Missing: $modelPath');
      if (libExists && !libShaMatches) {
        fail('$libPath sha256 does not match the pinned w5 build '
            '($expectedLibSha256) — re-verify before trusting this probe.');
      }
    });
    return;
  }

  setUpAll(() {
    Llama.libraryPath = libPath;
  });

  test('reports Metal (not CPU) when layers are offloaded to GPU', () {
    final llama = Llama(
      modelPath,
      modelParams: ModelParams()..nGpuLayers = 99,
      contextParams: ContextParams()
        ..nCtx = 512
        ..nBatch = 512,
    );
    try {
      final diag = llama.getDiagnostics();
      expect(diag.nGpuLayers, greaterThan(0),
          reason: 'sanity: GPU offload was actually requested');
      expect(llama.getBackendName(), isNot('CPU'),
          reason: 'native log showed 35/35 layers offloaded to GPU '
              '(MTL0 / Apple Silicon Metal device); diagnostics must not '
              'say CPU');
      expect(llama.getBackendName(), 'Metal');
    } finally {
      llama.dispose();
    }
  });

  test('reports CPU when constructed with zero GPU layers', () {
    final llama = Llama(
      modelPath,
      modelParams: ModelParams()..nGpuLayers = 0,
      contextParams: ContextParams()
        ..nCtx = 512
        ..nBatch = 512,
    );
    try {
      expect(llama.getDiagnostics().nGpuLayers, 0);
      expect(llama.getBackendName(), 'CPU');
    } finally {
      llama.dispose();
    }
  });
}
