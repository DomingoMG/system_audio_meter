import 'dart:async';

import 'src/audio_device_event.dart';
import 'src/audio_input_device.dart';
import 'src/audio_levels.dart';
import 'src/audio_output_device.dart';
import 'src/audio_silence_event.dart';
import 'src/audio_silence_stage.dart';
import 'src/audio_silence_tracker.dart';
import 'system_audio_meter_platform_interface.dart';

export 'src/audio_device_event.dart';
export 'src/audio_input_device.dart';
export 'src/audio_levels.dart';
export 'src/audio_output_device.dart';
export 'src/audio_silence_event.dart';
export 'src/audio_silence_stage.dart';
export 'src/audio_silence_state.dart';
export 'src/audio_silence_tracker.dart';

abstract class SystemAudioMeter {
  static SystemAudioMeter get instance => SystemAudioMeterPlatform.instance;

  Stream<AudioLevels> get outputLevels;

  @Deprecated('Use outputLevels instead.')
  Stream<AudioLevels> get levels;

  Stream<AudioLevels> get inputLevels;

  Stream<AudioDeviceEvent> get deviceEvents;

  Stream<AudioSilenceEvent> get silenceEvents;

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

  Future<void> enableSilenceDetection({
    required AudioDeviceFlow flow,
    required double threshold,
    required Duration duration,
  });

  Future<void> disableSilenceDetection({
    required AudioDeviceFlow flow,
  });

  Future<bool> get isRunning;

  Future<bool> get isInputRunning;

  AudioSilenceTracker createSilenceTracker({
    required List<AudioSilenceStage> stages,
  }) {
    return AudioSilenceTracker(
      events: silenceEvents,
      stages: stages,
    );
  }
}
