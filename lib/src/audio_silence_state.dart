import 'audio_device_event.dart';
import 'audio_silence_event.dart';
import 'audio_silence_stage.dart';

/// High-level silence state emitted by [AudioSilenceTracker].
enum AudioSilenceStateType {
  /// The flow is currently active or has just been reset back to active.
  active,

  /// The flow has just entered silence.
  silent,

  /// The flow remained silent long enough to enter a configured stage.
  stageChanged,
}

/// Derived silence state intended for UI and application logic.
///
/// Unlike [AudioSilenceEvent], this model is produced entirely in Dart and is
/// safe to customize in forks without touching the native capture backends.
class AudioSilenceState {
  const AudioSilenceState({
    required this.type,
    required this.flow,
    required this.isSilent,
    required this.silentFor,
    required this.updatedAt,
    this.currentStage,
    this.deviceId,
    this.deviceName,
    this.peakLevel = 0.0,
    this.sourceEventType,
  });

  /// Type of state transition represented by this update.
  final AudioSilenceStateType type;

  /// Flow associated with this state.
  final AudioDeviceFlow flow;

  /// Whether the flow is currently considered silent.
  final bool isSilent;

  /// Total time spent in silence for the current silent period.
  final Duration silentFor;

  /// Timestamp when this state object was emitted.
  final DateTime updatedAt;

  /// Currently active silence stage, if any.
  final AudioSilenceStage? currentStage;

  /// Device identifier associated with the current state, when available.
  final String? deviceId;

  /// Device name associated with the current state, when available.
  final String? deviceName;

  /// Most recent peak level known to the tracker.
  final double peakLevel;

  /// Native silence transition that originated this state, when applicable.
  final AudioSilenceEventType? sourceEventType;
}
