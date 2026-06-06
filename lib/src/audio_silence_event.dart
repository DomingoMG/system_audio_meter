import 'audio_device_event.dart';

/// Native silence transition type emitted by the plugin.
enum AudioSilenceEventType {
  /// The monitored flow remained below the configured threshold long enough to
  /// be considered silent.
  silenceStarted,

  /// The monitored flow rose above the configured threshold after being silent.
  silenceEnded,
}

/// Immutable low-level silence event emitted by [SystemAudioMeter.silenceEvents].
///
/// This event intentionally carries only the native transition information.
/// Richer UI-oriented escalation can be built in Dart with [AudioSilenceTracker].
class AudioSilenceEvent {
  const AudioSilenceEvent({
    required this.type,
    required this.flow,
    required this.peakLevel,
    required this.timestamp,
    this.deviceId,
    this.deviceName,
  });

  /// Type of silence transition that occurred.
  final AudioSilenceEventType type;

  /// Flow that triggered the silence transition.
  final AudioDeviceFlow flow;

  /// Peak level associated with the transition, normalized to `0.0..1.0`.
  final double peakLevel;

  /// Event timestamp parsed from the platform payload.
  final DateTime timestamp;

  /// Device identifier associated with the event, when available.
  final String? deviceId;

  /// Human-readable device name associated with the event, when available.
  final String? deviceName;

  /// Parses a platform channel payload into an [AudioSilenceEvent].
  factory AudioSilenceEvent.fromMap(Map<dynamic, dynamic> map) {
    return AudioSilenceEvent(
      type: _parseType(map['type']),
      flow: (map['flow'] as String?) == 'input'
          ? AudioDeviceFlow.input
          : AudioDeviceFlow.output,
      peakLevel: _clampPeak(map['peakLevel']),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        _readInt(map['timestamp']),
        isUtc: false,
      ),
      deviceId: map['deviceId'] as String?,
      deviceName: map['deviceName'] as String?,
    );
  }

  static AudioSilenceEventType _parseType(dynamic value) {
    switch (value) {
      case 'silenceStarted':
        return AudioSilenceEventType.silenceStarted;
      case 'silenceEnded':
        return AudioSilenceEventType.silenceEnded;
      default:
        throw ArgumentError.value(
          value,
          'type',
          'Unsupported silence event type.',
        );
    }
  }

  static double _clampPeak(dynamic value) {
    final peak = (value as num?)?.toDouble() ?? 0.0;
    if (peak.isNaN || peak.isInfinite) {
      return 0.0;
    }
    return peak.clamp(0.0, 1.0);
  }

  static int _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }
}
