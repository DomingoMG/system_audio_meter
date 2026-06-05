enum AudioDeviceEventKind {
  connected,
  disconnected,
}

enum AudioDeviceFlow {
  output,
  input,
}

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

  final AudioDeviceEventKind kind;
  final AudioDeviceFlow flow;
  final DateTime timestamp;
  final String? deviceId;
  final String? deviceName;
  final bool isDefault;
  final bool isSelected;

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
