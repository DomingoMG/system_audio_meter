/// Immutable description of an output device exposed by the plugin.
class AudioOutputDevice {
  const AudioOutputDevice({
    required this.id,
    required this.name,
    required this.isDefault,
  });

  /// Platform-specific device identifier.
  final String id;

  /// Human-readable device name.
  final String name;

  /// Whether this device is currently the system default output.
  final bool isDefault;

  /// Parses a platform channel payload into an [AudioOutputDevice].
  factory AudioOutputDevice.fromMap(Map<dynamic, dynamic> map) {
    return AudioOutputDevice(
      id: (map['id'] as String?) ?? '',
      name: (map['name'] as String?) ?? 'Unknown output device',
      isDefault: map['isDefault'] == true,
    );
  }
}
