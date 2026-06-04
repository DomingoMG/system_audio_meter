import 'dart:async';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_audio_meter/system_audio_meter.dart';
import 'package:system_audio_meter/system_audio_meter_method_channel.dart';
import 'package:system_audio_meter/system_audio_meter_platform_interface.dart';

class MockSystemAudioMeterPlatform
    with MockPlatformInterfaceMixin
    implements SystemAudioMeterPlatform {
  @override
  Stream<AudioLevels> get levels => const Stream<AudioLevels>.empty();

  @override
  Future<AudioOutputDevice?> getCurrentOutputDevice() => Future.value(
        const AudioOutputDevice(
            id: 'default', name: 'Default', isDefault: true),
      );

  @override
  Future<List<AudioOutputDevice>> getOutputDevices() => Future.value(
        const <AudioOutputDevice>[
          AudioOutputDevice(id: 'default', name: 'Default', isDefault: true),
        ],
      );

  @override
  Future<bool> get isRunning => Future.value(true);

  @override
  Future<void> setOutputDevice(String? deviceId) => Future.value();

  @override
  Future<void> start() => Future.value();

  @override
  Future<void> stop() => Future.value();
}

void main() {
  final SystemAudioMeterPlatform initialPlatform =
      SystemAudioMeterPlatform.instance;

  test('$MethodChannelSystemAudioMeter is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelSystemAudioMeter>());
  });

  test('returns devices from the platform interface', () async {
    MockSystemAudioMeterPlatform fakePlatform = MockSystemAudioMeterPlatform();
    SystemAudioMeterPlatform.instance = fakePlatform;
    final SystemAudioMeter systemAudioMeterPlugin = SystemAudioMeter.instance;

    final devices = await systemAudioMeterPlugin.getOutputDevices();
    expect(devices.single.name, 'Default');
    expect(await systemAudioMeterPlugin.isRunning, isTrue);
  });
}
