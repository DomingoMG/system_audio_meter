/// Type of device lifecycle transition reported by the plugin.
enum AudioDeviceEventKind {
  /// A previously unavailable device became available.
  connected,

  /// A previously available device became unavailable.
  disconnected,
}

/// Audio flow associated with a meter, device event, or silence event.
enum AudioDeviceFlow {
  /// Speaker, headset, or other system output flow.
  output,

  /// Microphone or other capture/input flow.
  input,
}

/// Immutable device lifecycle event emitted by [SystemAudioMeter.deviceEvents].
class AudioDeviceEvent {
  const AudioDeviceEvent({
    required this.kind,
    required this.flow,
    required this.timestamp,
    this.deviceId,
    this.deviceName,
    required this.isDefault,
    required this.isSelected,
  });

  /// Whether this event describes a connection or disconnection.
  final AudioDeviceEventKind kind;

  /// Flow affected by the device transition.
  final AudioDeviceFlow flow;

  /// Event timestamp parsed from the platform payload.
  final DateTime timestamp;

  /// Stable platform device identifier, when available.
  final String? deviceId;

  /// Human-readable device name, when available.
  final String? deviceName;

  /// Whether the device was the system default at the time of the event.
  final bool isDefault;

  /// Whether the device matched the plugin's currently selected target.
  final bool isSelected;

  /// Parses a platform channel payload into an [AudioDeviceEvent].
  factory AudioDeviceEvent.fromMap(Map<dynamic, dynamic> map) {
    return AudioDeviceEvent(
      kind: (map['kind'] as String?) == 'connected'
          ? AudioDeviceEventKind.connected
          : AudioDeviceEventKind.disconnected,
      flow: (map['flow'] as String?) == 'input'
          ? AudioDeviceFlow.input
          : AudioDeviceFlow.output,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        _readInt(map['timestamp']),
        isUtc: false,
      ),
      deviceId: map['deviceId'] as String?,
      deviceName: map['deviceName'] as String?,
      isDefault: map['isDefault'] == true,
      isSelected: map['isSelected'] == true,
    );
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
