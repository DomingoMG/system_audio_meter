import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_audio_meter/system_audio_meter_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelSystemAudioMeter platform = MethodChannelSystemAudioMeter();
  const MethodChannel channel = MethodChannel('system_audio_meter');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          return '42';
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('isRunning defaults to false when the platform returns null', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          return null;
        });

    expect(await platform.isRunning, isFalse);
  });
}
