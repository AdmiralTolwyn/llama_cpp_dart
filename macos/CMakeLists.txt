# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

# Project-level configuration.
set(PROJECT_NAME "llama_cpp_dart")
project(${PROJECT_NAME} LANGUAGES CXX)

# Disable macOS app bundles for targets inside llama.cpp (tools/examples).
# Without this, CMake creates .app bundles that the Flutter build system
# doesn't know how to handle.
set(CMAKE_MACOSX_BUNDLE FALSE)

include(GNUInstallDirs)
set(CMAKE_INSTALL_LIBDIR lib)

# Build llama.cpp + mtmd from source.
# Metal support is automatically enabled on Apple Silicon via CMake feature detection.
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" src)
