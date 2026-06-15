Pod::Spec.new do |s|
  s.name             = 'thestage_apple_sdk'
  s.version          = '0.0.1'
  s.summary          = 'Flutter plugin for TheStage Swift SDK on Apple platforms.'
  s.description      = 'Flutter plugin for TheStage Swift SDK (CocoaPods fallback — prefer SPM).'
  s.homepage         = 'https://example.com/thestage_apple_sdk'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'TheStage' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'thestage_apple_sdk/Sources/thestage_apple_sdk/**/*'
  s.dependency 'Flutter'
  s.static_framework = true
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
  s.platform = :ios, '18.0'
  s.swift_version = '5.10'
end
