import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'src/audio_levels.dart';
import 'src/audio_output_device.dart';
import 'system_audio_meter_platform_interface.dart';

/// An implementation of [SystemAudioMeterPlatform] that uses method channels.
class MethodChannelSystemAudioMeter extends SystemAudioMeterPlatform {
  @visibleForTesting
  final MethodChannel methodChannel = const MethodChannel('system_audio_meter');

  @visibleForTesting
  final EventChannel eventChannel =
      const EventChannel('system_audio_meter/levels');

  Stream<AudioLevels>? _levels;

  @override
  Stream<AudioLevels> get levels =>
      _levels ??= eventChannel.receiveBroadcastStream().map((dynamic event) =>
          AudioLevels.fromMap(event as Map<dynamic, dynamic>));

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
  Future<void> setOutputDevice(String? deviceId) {
    return methodChannel
        .invokeMethod<void>('setOutputDevice', <String, Object?>{
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
  Future<void> start() {
    return methodChannel.invokeMethod<void>('start');
  }

  @override
  Future<void> stop() {
    return methodChannel.invokeMethod<void>('stop');
  }

  @override
  Future<bool> get isRunning async {
    return await methodChannel.invokeMethod<bool>('isRunning') ?? false;
  }
}
