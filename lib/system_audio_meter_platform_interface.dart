import 'dart:async';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'system_audio_meter_method_channel.dart';
import 'system_audio_meter.dart';

abstract class SystemAudioMeterPlatform extends PlatformInterface
    implements SystemAudioMeter {
  /// Constructs a SystemAudioMeterPlatform.
  SystemAudioMeterPlatform() : super(token: _token);

  static final Object _token = Object();

  static SystemAudioMeterPlatform _instance = MethodChannelSystemAudioMeter();

  /// The default instance of [SystemAudioMeterPlatform] to use.
  ///
  /// Defaults to [MethodChannelSystemAudioMeter].
  static SystemAudioMeterPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [SystemAudioMeterPlatform] when
  /// they register themselves.
  static set instance(SystemAudioMeterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  @override
  Stream<AudioLevels> get outputLevels =>
      throw UnimplementedError('outputLevels has not been implemented.');

  @override
  Stream<AudioLevels> get levels =>
      outputLevels;

  @override
  Stream<AudioLevels> get inputLevels =>
      throw UnimplementedError('inputLevels has not been implemented.');

  @override
  Stream<AudioDeviceEvent> get deviceEvents =>
      throw UnimplementedError('deviceEvents has not been implemented.');

  @override
  Stream<AudioSilenceEvent> get silenceEvents =>
      throw UnimplementedError('silenceEvents has not been implemented.');

  @override
  Future<List<AudioOutputDevice>> getOutputDevices() =>
      throw UnimplementedError('getOutputDevices() has not been implemented.');

  @override
  Future<List<AudioInputDevice>> getInputDevices() =>
      throw UnimplementedError('getInputDevices() has not been implemented.');

  @override
  Future<void> setOutputDevice(String? deviceId) =>
      throw UnimplementedError('setOutputDevice() has not been implemented.');

  @override
  Future<void> setInputDevice(String? deviceId) =>
      throw UnimplementedError('setInputDevice() has not been implemented.');

  @override
  Future<AudioOutputDevice?> getCurrentOutputDevice() =>
      throw UnimplementedError(
        'getCurrentOutputDevice() has not been implemented.',
      );

  @override
  Future<AudioInputDevice?> getCurrentInputDevice() =>
      throw UnimplementedError(
        'getCurrentInputDevice() has not been implemented.',
      );

  @override
  Future<void> start() =>
      throw UnimplementedError('start() has not been implemented.');

  @override
  Future<void> startInput() =>
      throw UnimplementedError('startInput() has not been implemented.');

  @override
  Future<void> stop() =>
      throw UnimplementedError('stop() has not been implemented.');

  @override
  Future<void> stopInput() =>
      throw UnimplementedError('stopInput() has not been implemented.');

  @override
  Future<void> enableSilenceDetection({
    required AudioDeviceFlow flow,
    required double threshold,
    required Duration duration,
  }) => throw UnimplementedError(
        'enableSilenceDetection() has not been implemented.',
      );

  @override
  Future<void> disableSilenceDetection({
    required AudioDeviceFlow flow,
  }) =>
      throw UnimplementedError(
        'disableSilenceDetection() has not been implemented.',
      );

  @override
  Future<bool> get isRunning =>
      throw UnimplementedError('isRunning has not been implemented.');

  @override
  Future<bool> get isInputRunning =>
      throw UnimplementedError('isInputRunning has not been implemented.');

  @override
  AudioSilenceTracker createSilenceTracker({
    required List<AudioSilenceStage> stages,
  }) {
    return AudioSilenceTracker(
      events: silenceEvents,
      stages: stages,
    );
  }
}
