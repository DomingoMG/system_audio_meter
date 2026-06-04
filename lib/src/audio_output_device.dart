class AudioOutputDevice {
  const AudioOutputDevice({
    required this.id,
    required this.name,
    required this.isDefault,
  });

  final String id;
  final String name;
  final bool isDefault;

  factory AudioOutputDevice.fromMap(Map<dynamic, dynamic> map) {
    return AudioOutputDevice(
      id: (map['id'] as String?) ?? '',
      name: (map['name'] as String?) ?? 'Unknown output device',
      isDefault: map['isDefault'] == true,
    );
  }
}
