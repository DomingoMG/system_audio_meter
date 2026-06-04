import 'dart:async';

import 'src/audio_levels.dart';
import 'src/audio_output_device.dart';
import 'system_audio_meter_platform_interface.dart';

export 'src/audio_levels.dart';
export 'src/audio_output_device.dart';

abstract class SystemAudioMeter {
  static SystemAudioMeter get instance => SystemAudioMeterPlatform.instance;

  Stream<AudioLevels> get levels;

  Future<List<AudioOutputDevice>> getOutputDevices();

  Future<void> setOutputDevice(String? deviceId);

  Future<AudioOutputDevice?> getCurrentOutputDevice();

  Future<void> start();

  Future<void> stop();

  Future<bool> get isRunning;
}
