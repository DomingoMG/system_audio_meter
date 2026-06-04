class AudioLevels {
  const AudioLevels({
    required this.leftPeak,
    required this.rightPeak,
    required this.timestamp,
    this.outputDeviceId,
    this.outputDeviceName,
  });

  final double leftPeak;
  final double rightPeak;
  final DateTime timestamp;
  final String? outputDeviceId;
  final String? outputDeviceName;

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
