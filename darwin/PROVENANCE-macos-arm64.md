# Provenance: `ios/Llama.xcframework/macos-arm64/Llama.framework`

This records how the macOS slice of the committed xcframework was
converted from the iOS-shallow layout to the Apple versioned-bundle
layout macOS's Xcode Validate phase requires, on `macos/versioned-framework`.

## Fork ref

Built from `llama_cpp_dart` fork commit `203a063a7f5cdb20537e789a95585af67ba8b37d`.

## No recompilation

**The compiled code is byte-identical to the committed
`203a063a…` binary.** Only the install-name load command and the code
signature changed. Nothing was rebuilt from source; `src/llama.cpp` was
never touched or even checked out for this change.

## What produced it

`darwin/repackage_macos_slice.sh`, invoked with no arguments (its
defaults: `ios/Llama.xcframework` in this repo, and the embedded expected
input sha256 below), run once against a scratch copy to exercise it and
once against this tree to regenerate the committed artifact. It shares
its versioning/signing steps with `build_macos_slice()` in
`darwin/create_xcframework.sh` via `darwin/macos_framework_layout.sh` —
see those files for the layout itself.

## Binary hashes and sizes

| | sha256 | size (bytes) |
|---|---|---|
| Input (macos-arm64, iOS-shallow, committed at `203a063a…`) | `5964069fbeb193ed0eb8b13a8e78e1c17ac6c54efc44d029326f8b02445f0b06` | 6073536 |
| Output (macos-arm64, versioned, this commit) | `66fcb196680dc888d40f98d484835203270105b9e89f66411a731a78f4406276` | 6103680 |

The output is larger only because of the added Mach-O load command
(the versioned install name is a longer string than the shallow one) and
the ad-hoc code signature; no code bytes changed.

## iOS slices — unchanged

Both iOS slices were copied into the reassembled xcframework unchanged
and diffed (`diff -r`) against the tree's originals before anything was
replaced; both diffs were empty.

| Slice | binary sha256 | size (bytes) |
|---|---|---|
| ios-arm64 | `ab454c2d8c06ef19d1c74cd80cc5b6637f8b98b4a61c51224806699d116a9f3e` | 5981960 |
| ios-arm64_x86_64-simulator | `cfaaa96a7ef7ee261653d93b8360faa0393d0b603dda8775e1092f17f4b41fac` | 12570032 |

## Output binary inspection

```
$ vtool -show-build ios/Llama.xcframework/macos-arm64/Llama.framework/Versions/A/Llama
Load command 10
      cmd LC_BUILD_VERSION
  cmdsize 32
 platform MACOS
    minos 12.0
      sdk 26.2
   ntools 1
     tool LD
  version 1230.1

$ lipo -archs ios/Llama.xcframework/macos-arm64/Llama.framework/Versions/A/Llama
arm64
```

`codesign --verify --deep --strict` passes on both the standalone
versioned slice and the assembled xcframework's macos-arm64 slice.

## Toolchain

- Flutter 3.44.8 (stable)
- CocoaPods 1.17.0
- Xcode 26.6 (build 17F113)
- Apple clang 21.0.0 (clang-2100.1.1.101)
- macOS 26.6.2, arm64 (Apple Silicon host)
