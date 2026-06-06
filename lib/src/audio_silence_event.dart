import 'audio_device_event.dart';

enum AudioSilenceEventType {
  silenceStarted,
  silenceEnded,
}

class AudioSilenceEvent {
  const AudioSilenceEvent({
    required this.type,
    required this.flow,
    required this.peakLevel,
    required this.timestamp,
    this.deviceId,
    this.deviceName,
  });

  final AudioSilenceEventType type;
  final AudioDeviceFlow flow;
  final double peakLevel;
  final DateTime timestamp;
  final String? deviceId;
  final String? deviceName;

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
