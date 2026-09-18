# Vendors the macOS slice of the same Llama.xcframework the iOS pod
# vendors — macos/Llama.xcframework is a committed symlink to
# ../ios/Llama.xcframework, not a second copy. Apple Silicon (arm64)
# only, matching the macos-arm64 slice that is actually built
# (owner ruling: no Intel macOS slice).
Pod::Spec.new do |s|
  s.name             = 'llama_cpp_dart'
  s.version          = '0.0.1'
  s.summary          = 'Flutter plugin for llama.cpp'
  s.description      = <<-DESC
  A Flutter plugin wrapper for llama.cpp to run LLM models locally.
                       DESC
  s.homepage         = 'https://github.com/netdur/llama_cpp_dart'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Your Name' => 'your-email@example.com' }
  s.source           = { :path => '.' }

  s.platform         = :osx, '12.0'
  s.swift_version    = '5.0'

  s.source_files     = []
  s.vendored_frameworks = 'Llama.xcframework'

  s.dependency 'FlutterMacOS'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
