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

/// Public Flutter API for the `system_audio_meter` plugin.
///
/// This package exposes real-time peak metering for desktop output and input
/// devices, plus optional silence detection and UI-side silence stage tracking.
///
/// Use [instance] to access the active platform implementation.
abstract class SystemAudioMeter {
  /// Returns the active plugin instance for the current platform.
  static SystemAudioMeter get instance => SystemAudioMeterPlatform.instance;

  /// Broadcast stream of output peak updates.
  ///
  /// Each event represents the most recent normalized stereo peaks emitted by
  /// the native output meter.
  Stream<AudioLevels> get outputLevels;

  /// Backward-compatible alias for [outputLevels].
  ///
  /// New code should prefer [outputLevels] because it is explicit about the
  /// audio flow being monitored.
  @Deprecated('Use outputLevels instead.')
  Stream<AudioLevels> get levels;

  /// Broadcast stream of input peak updates.
  ///
  /// Each event represents the most recent normalized stereo peaks emitted by
  /// the native input meter.
  Stream<AudioLevels> get inputLevels;

  /// Broadcast stream of device connection and disconnection events.
  Stream<AudioDeviceEvent> get deviceEvents;

  /// Broadcast stream of low-level silence transition events.
  ///
  /// These events are emitted by the native layer when a configured input or
  /// output flow enters or leaves silence. They are intentionally minimal and
  /// are a good base for building richer UI-specific state in Dart.
  Stream<AudioSilenceEvent> get silenceEvents;

  /// Returns the currently available output devices.
  Future<List<AudioOutputDevice>> getOutputDevices();

  /// Returns the currently available input devices.
  Future<List<AudioInputDevice>> getInputDevices();

  /// Selects the output device to monitor.
  ///
  /// Pass `null` to switch back to the system default output device.
  Future<void> setOutputDevice(String? deviceId);

  /// Selects the input device to monitor.
  ///
  /// Pass `null` to switch back to the system default input device.
  Future<void> setInputDevice(String? deviceId);

  /// Returns the current output device used by the plugin, if known.
  Future<AudioOutputDevice?> getCurrentOutputDevice();

  /// Returns the current input device used by the plugin, if known.
  Future<AudioInputDevice?> getCurrentInputDevice();

  /// Starts output metering.
  Future<void> start();

  /// Starts input metering.
  Future<void> startInput();

  /// Stops output metering.
  Future<void> stop();

  /// Stops input metering.
  Future<void> stopInput();

  /// Enables native silence detection for the given [flow].
  ///
  /// The [threshold] must be between `0.0` and `1.0`.
  ///
  /// The [duration] defines how long the peak level must remain below the
  /// threshold before the flow is considered silent.
  Future<void> enableSilenceDetection({
    required AudioDeviceFlow flow,
    required double threshold,
    required Duration duration,
  });

  /// Disables native silence detection for the given [flow].
  Future<void> disableSilenceDetection({
    required AudioDeviceFlow flow,
  });

  /// Whether output metering is currently active.
  Future<bool> get isRunning;

  /// Whether input metering is currently active.
  Future<bool> get isInputRunning;

  /// Creates a Dart-side silence tracker on top of [silenceEvents].
  ///
  /// This is the recommended way to build UI-specific escalation rules such as
  /// "warning after 5 seconds" or "critical after 10 seconds" without changing
  /// the native plugin implementation.
  AudioSilenceTracker createSilenceTracker({
    required List<AudioSilenceStage> stages,
  }) {
    return AudioSilenceTracker(
      events: silenceEvents,
      stages: stages,
    );
  }
}
