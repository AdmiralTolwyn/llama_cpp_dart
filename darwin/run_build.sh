#!/bin/bash

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 <llama_cpp_path> <dev_team>"
    exit 1
fi

llama_cpp_path="$1"
dev_team="$2"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
output_base_dir="${script_dir}/.."

build_for_platform() {
    local platform="$1"
    local build_dir="build_${platform}"
    local output_dir="${output_base_dir}/bin/${platform}"
    local deployment_target=13.3

    echo "Building for platform: ${platform} with deployment target iOS ${deployment_target}"
    
    rm -rf "${build_dir}"
    mkdir -p "${build_dir}"
    cd "${build_dir}"

    # Build as STATIC libraries — we'll merge them into a single dylib below.
    # This avoids nested Frameworks/ inside the .framework bundle, which Apple
    # rejects for App Store submission (ITMS-90206).
    cmake -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON \
          -DBUILD_SHARED_LIBS=OFF \
          -DLLAMA_CURL=OFF \
          -DLLAMA_BUILD_TESTS=OFF \
          -DLLAMA_BUILD_EXAMPLES=OFF \
          -DLLAMA_BUILD_SERVER=OFF \
          -DLLAMA_BUILD_TOOLS=ON \
          -DLLAMA_BUILD_COMMON=ON \
          -DLLAMA_OPENSSL=OFF \
          -DCMAKE_PROJECT_INCLUDE="${script_dir}/no_bundle.cmake" \
          -DCMAKE_BUILD_TYPE=Release \
          -G Xcode \
          -DCMAKE_TOOLCHAIN_FILE="${script_dir}/ios-arm64.toolchain.cmake" \
          -DPLATFORM="${platform}" \
          -DDEPLOYMENT_TARGET=${deployment_target} \
          -DENABLE_BITCODE=0 \
          -DENABLE_ARC=0 \
          -DENABLE_VISIBILITY=1 \
          -DENABLE_STRICT_TRY_COMPILE=1 \
          -DCMAKE_XCODE_ATTRIBUTE_DEVELOPMENT_TEAM="${dev_team}" \
          -DCMAKE_XCODE_ATTRIBUTE_ENABLE_BITCODE=NO \
          -DCMAKE_INSTALL_PREFIX="./install" \
          ..

    cmake --build . --config Release --parallel
    cmake --install . --config Release

    mkdir -p "${output_dir}"

    # Collect all static libraries produced by the build
    # NOTE: We skip libllama-common.a — it's the CLI utility library that
    # requires httplib/curl and is NOT used by the Dart FFI bindings.
    local static_libs=()
    for lib in install/lib/libllama.a install/lib/libggml.a install/lib/libggml-base.a \
               install/lib/libggml-metal.a install/lib/libggml-cpu.a \
               install/lib/libggml-blas.a install/lib/libmtmd.a; do
        if [ -f "$lib" ]; then
            static_libs+=("$lib")
            echo "  Found static lib: $(basename "$lib")"
        else
            echo "  ⚠️  Not found (optional): $(basename "$lib")"
        fi
    done

    # Determine linker flags based on platform
    local platform_flags=""
    case "$platform" in
        OS64)
            platform_flags="-arch arm64 -isysroot $(xcrun --sdk iphoneos --show-sdk-path) -miphoneos-version-min=${deployment_target}"
            ;;
        SIMULATORARM64)
            platform_flags="-arch arm64 -isysroot $(xcrun --sdk iphonesimulator --show-sdk-path) -mios-simulator-version-min=${deployment_target}"
            ;;
        SIMULATOR64)
            platform_flags="-arch x86_64 -isysroot $(xcrun --sdk iphonesimulator --show-sdk-path) -mios-simulator-version-min=${deployment_target}"
            ;;
        MAC_ARM64)
            platform_flags="-arch arm64 -isysroot $(xcrun --sdk macosx --show-sdk-path) -mmacosx-version-min=12.0"
            ;;
    esac

    # Merge all static libs into a single shared libllama.dylib
    echo "🔗 Linking all static libs into single libllama.dylib..."
    xcrun clang++ -dynamiclib \
        ${platform_flags} \
        -install_name "@rpath/libllama.dylib" \
        -Wl,-all_load \
        "${static_libs[@]}" \
        -framework Accelerate \
        -framework Metal \
        -framework MetalKit \
        -framework Foundation \
        -lc++ \
        -o "${output_dir}/libllama.dylib"

    # Ad-hoc sign
    codesign --remove-signature "${output_dir}/libllama.dylib" 2>/dev/null || true
    codesign --force --sign - "${output_dir}/libllama.dylib"

    # Verify
    if otool -l "${output_dir}/libllama.dylib" | grep -q "LC_VERSION_MIN_IPHONEOS\|LC_BUILD_VERSION"; then
        echo "✅ libllama.dylib - platform info preserved"
    else
        echo "❌ libllama.dylib - platform info missing"
    fi

    echo "📦 Single dylib: $(du -h "${output_dir}/libllama.dylib" | cut -f1)"
    cd ..
}

main() {
    local platform=${3:-"OS64"}
    
    cp "${script_dir}/ios-arm64.toolchain.cmake" "${llama_cpp_path}/"

    pushd "${llama_cpp_path}" > /dev/null

    build_for_platform "${platform}"

    popd > /dev/null
    
    echo "Build completed successfully for ${platform}."
}

main "$@"
