import 'dart:async';

import 'src/audio_device_event.dart';
import 'src/audio_input_device.dart';
import 'src/audio_levels.dart';
import 'src/audio_output_device.dart';
import 'system_audio_meter_platform_interface.dart';

export 'src/audio_device_event.dart';
export 'src/audio_input_device.dart';
export 'src/audio_levels.dart';
export 'src/audio_output_device.dart';

abstract class SystemAudioMeter {
  static SystemAudioMeter get instance => SystemAudioMeterPlatform.instance;

  Stream<AudioLevels> get levels;

  Stream<AudioLevels> get inputLevels;

  Stream<AudioDeviceEvent> get deviceEvents;

  Future<List<AudioOutputDevice>> getOutputDevices();

  Future<List<AudioInputDevice>> getInputDevices();

  Future<void> setOutputDevice(String? deviceId);

  Future<void> setInputDevice(String? deviceId);

  Future<AudioOutputDevice?> getCurrentOutputDevice();

  Future<AudioInputDevice?> getCurrentInputDevice();

  Future<void> start();

  Future<void> startInput();

  Future<void> stop();

  Future<void> stopInput();

  Future<bool> get isRunning;

  Future<bool> get isInputRunning;
}
