import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'src/audio_device_event.dart';
import 'src/audio_input_device.dart';
import 'src/audio_levels.dart';
import 'src/audio_output_device.dart';
import 'src/audio_silence_event.dart';
import 'src/audio_silence_stage.dart';
import 'src/audio_silence_tracker.dart';
import 'system_audio_meter_platform_interface.dart';

/// An implementation of [SystemAudioMeterPlatform] that uses method channels.
class MethodChannelSystemAudioMeter extends SystemAudioMeterPlatform {
  @visibleForTesting
  final MethodChannel methodChannel = const MethodChannel('system_audio_meter');

  @visibleForTesting
  final EventChannel eventChannel =
      const EventChannel('system_audio_meter/levels');

  @visibleForTesting
  final EventChannel inputEventChannel =
      const EventChannel('system_audio_meter/input_levels');

  @visibleForTesting
  final EventChannel deviceEventChannel =
      const EventChannel('system_audio_meter/device_events');

  @visibleForTesting
  final EventChannel silenceEventChannel =
      const EventChannel('system_audio_meter/silence_events');

  Stream<AudioLevels>? _levels;
  Stream<AudioLevels>? _inputLevels;
  Stream<AudioDeviceEvent>? _deviceEvents;
  Stream<AudioSilenceEvent>? _silenceEvents;

  @override
  Stream<AudioLevels> get outputLevels =>
      _levels ??= eventChannel.receiveBroadcastStream().map((dynamic event) =>
          AudioLevels.fromMap(event as Map<dynamic, dynamic>));

  @override
  Stream<AudioLevels> get levels => outputLevels;

  @override
  Stream<AudioLevels> get inputLevels => _inputLevels ??=
      inputEventChannel.receiveBroadcastStream().map((dynamic event) =>
          AudioLevels.fromMap(event as Map<dynamic, dynamic>));

  @override
  Stream<AudioDeviceEvent> get deviceEvents => _deviceEvents ??=
      deviceEventChannel.receiveBroadcastStream().map((dynamic event) =>
          AudioDeviceEvent.fromMap(event as Map<dynamic, dynamic>));

  @override
  Stream<AudioSilenceEvent> get silenceEvents => _silenceEvents ??=
      silenceEventChannel.receiveBroadcastStream().map((dynamic event) =>
          AudioSilenceEvent.fromMap(event as Map<dynamic, dynamic>));

  @override
  Future<List<AudioOutputDevice>> getOutputDevices() async {
    final devices =
        await methodChannel.invokeListMethod<dynamic>('getOutputDevices') ??
            const <dynamic>[];
    return devices
        .map((dynamic device) =>
            AudioOutputDevice.fromMap(device as Map<dynamic, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<List<AudioInputDevice>> getInputDevices() async {
    final devices =
        await methodChannel.invokeListMethod<dynamic>('getInputDevices') ??
            const <dynamic>[];
    return devices
        .map((dynamic device) =>
            AudioInputDevice.fromMap(device as Map<dynamic, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<void> setOutputDevice(String? deviceId) {
    return methodChannel
        .invokeMethod<void>('setOutputDevice', <String, Object?>{
      'deviceId': deviceId,
    });
  }

  @override
  Future<void> setInputDevice(String? deviceId) {
    return methodChannel.invokeMethod<void>('setInputDevice', <String, Object?>{
      'deviceId': deviceId,
    });
  }

  @override
  Future<AudioOutputDevice?> getCurrentOutputDevice() async {
    final device =
        await methodChannel.invokeMethod<dynamic>('getCurrentOutputDevice');
    if (device == null) {
      return null;
    }
    return AudioOutputDevice.fromMap(device as Map<dynamic, dynamic>);
  }

  @override
  Future<AudioInputDevice?> getCurrentInputDevice() async {
    final device =
        await methodChannel.invokeMethod<dynamic>('getCurrentInputDevice');
    if (device == null) {
      return null;
    }
    return AudioInputDevice.fromMap(device as Map<dynamic, dynamic>);
  }

  @override
  Future<void> start() {
    return methodChannel.invokeMethod<void>('start');
  }

  @override
  Future<void> startInput() {
    return methodChannel.invokeMethod<void>('startInput');
  }

  @override
  Future<void> stop() {
    return methodChannel.invokeMethod<void>('stop');
  }

  @override
  Future<void> stopInput() {
    return methodChannel.invokeMethod<void>('stopInput');
  }

  @override
  Future<void> enableSilenceDetection({
    required AudioDeviceFlow flow,
    required double threshold,
    required Duration duration,
  }) {
    return methodChannel.invokeMethod<void>(
      'enableSilenceDetection',
      <String, Object?>{
        'flow': flow == AudioDeviceFlow.input ? 'input' : 'output',
        'threshold': threshold,
        'durationMs': duration.inMilliseconds,
      },
    );
  }

  @override
  Future<void> disableSilenceDetection({
    required AudioDeviceFlow flow,
  }) {
    return methodChannel.invokeMethod<void>(
      'disableSilenceDetection',
      <String, Object?>{
        'flow': flow == AudioDeviceFlow.input ? 'input' : 'output',
      },
    );
  }

  @override
  AudioSilenceTracker createSilenceTracker({
    required List<AudioSilenceStage> stages,
  }) {
    return AudioSilenceTracker(
      events: silenceEvents,
      stages: stages,
    );
  }

  @override
  Future<bool> get isRunning async {
    return await methodChannel.invokeMethod<bool>('isRunning') ?? false;
  }

  @override
  Future<bool> get isInputRunning async {
    return await methodChannel.invokeMethod<bool>('isInputRunning') ?? false;
  }
}
