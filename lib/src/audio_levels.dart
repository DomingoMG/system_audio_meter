/// Immutable peak meter update emitted by the plugin.
///
/// Peak values are normalized to the `0.0..1.0` range before they reach Dart.
class AudioLevels {
  const AudioLevels({
    required this.leftPeak,
    required this.rightPeak,
    required this.timestamp,
    this.outputDeviceId,
    this.outputDeviceName,
    this.inputDeviceId,
    this.inputDeviceName,
  });

  /// Peak value for the left channel, normalized to `0.0..1.0`.
  final double leftPeak;

  /// Peak value for the right channel, normalized to `0.0..1.0`.
  final double rightPeak;

  /// Event timestamp parsed from the platform payload.
  final DateTime timestamp;

  /// Output device identifier when this event comes from output metering.
  final String? outputDeviceId;

  /// Output device name when this event comes from output metering.
  final String? outputDeviceName;

  /// Input device identifier when this event comes from input metering.
  final String? inputDeviceId;

  /// Input device name when this event comes from input metering.
  final String? inputDeviceName;

  /// Parses a platform channel payload into an [AudioLevels] instance.
  factory AudioLevels.fromMap(Map<dynamic, dynamic> map) {
    return AudioLevels(
      leftPeak: _clampPeak(map['leftPeak']),
      rightPeak: _clampPeak(map['rightPeak']),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        _readInt(map['timestamp']),
        isUtc: false,
      ),
      outputDeviceId: map['outputDeviceId'] as String?,
      outputDeviceName: map['outputDeviceName'] as String?,
      inputDeviceId: map['inputDeviceId'] as String?,
      inputDeviceName: map['inputDeviceName'] as String?,
    );
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
