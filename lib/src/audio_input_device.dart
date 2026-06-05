class AudioInputDevice {
  const AudioInputDevice({
    required this.id,
    required this.name,
    required this.isDefault,
  });

  final String id;
  final String name;
  final bool isDefault;

  factory AudioInputDevice.fromMap(Map<dynamic, dynamic> map) {
    return AudioInputDevice(
      id: (map['id'] as String?) ?? '',
      name: (map['name'] as String?) ?? 'Unknown input device',
      isDefault: map['isDefault'] == true,
    );
  }
}
