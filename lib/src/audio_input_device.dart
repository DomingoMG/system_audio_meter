/// Immutable description of an input device exposed by the plugin.
class AudioInputDevice {
  const AudioInputDevice({
    required this.id,
    required this.name,
    required this.isDefault,
  });

  /// Platform-specific device identifier.
  final String id;

  /// Human-readable device name.
  final String name;

  /// Whether this device is currently the system default input.
  final bool isDefault;

  /// Parses a platform channel payload into an [AudioInputDevice].
  factory AudioInputDevice.fromMap(Map<dynamic, dynamic> map) {
    return AudioInputDevice(
      id: (map['id'] as String?) ?? '',
      name: (map['name'] as String?) ?? 'Unknown input device',
      isDefault: map['isDefault'] == true,
    );
  }
}
