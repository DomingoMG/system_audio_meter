import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_audio_meter/system_audio_meter.dart';
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

  test('enableSilenceDetection sends validated arguments to the platform', () async {
    MethodCall? capturedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      capturedCall = methodCall;
      return null;
    });

    await platform.enableSilenceDetection(
      flow: AudioDeviceFlow.output,
      threshold: 0.02,
      duration: const Duration(milliseconds: 800),
    );

    expect(capturedCall?.method, 'enableSilenceDetection');
    expect(
      capturedCall?.arguments,
      <String, Object?>{
        'flow': 'output',
        'threshold': 0.02,
        'durationMs': 800,
      },
    );
  });

  test('AudioSilenceEvent parses silenceStarted payloads', () {
    final event = AudioSilenceEvent.fromMap(<String, Object?>{
      'type': 'silenceStarted',
      'flow': 'input',
      'peakLevel': 0.004,
      'timestamp': 1710000000000,
      'deviceId': 'mic-1',
      'deviceName': 'Studio Mic',
    });

    expect(event.type, AudioSilenceEventType.silenceStarted);
    expect(event.flow, AudioDeviceFlow.input);
    expect(event.peakLevel, 0.004);
    expect(event.deviceId, 'mic-1');
    expect(event.deviceName, 'Studio Mic');
    expect(
      event.timestamp.millisecondsSinceEpoch,
      1710000000000,
    );
  });

  test('AudioSilenceEvent clamps invalid peak values', () {
    final event = AudioSilenceEvent.fromMap(<String, Object?>{
      'type': 'silenceEnded',
      'flow': 'output',
      'peakLevel': 8.0,
      'timestamp': 1710000004000,
    });

    expect(event.type, AudioSilenceEventType.silenceEnded);
    expect(event.flow, AudioDeviceFlow.output);
    expect(event.peakLevel, 1.0);
  });
}
