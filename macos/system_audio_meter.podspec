#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint system_audio_meter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'system_audio_meter'
  s.version          = '0.3.0'
  s.summary          = 'Real-time desktop audio level meter for Flutter.'
  s.description      = <<-DESC
Real-time desktop audio level meter for Flutter with macOS and Windows native backends.
                       DESC
  s.homepage         = 'https://pub.dev/packages/system_audio_meter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'system_audio_meter' => 'noreply@example.com' }

  s.source           = { :path => '.' }
  s.source_files = 'system_audio_meter/Sources/system_audio_meter/**/*'

  # If your plugin requires a privacy manifest, for example if it collects user
  # data, update the PrivacyInfo.xcprivacy file to describe your plugin's
  # privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'system_audio_meter_privacy' => ['system_audio_meter/Sources/system_audio_meter/PrivacyInfo.xcprivacy']}

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '14.2'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
