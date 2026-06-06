# API Reference

This page summarizes the public Dart API exposed by `system_audio_meter`.

## Entry point

```dart
final meter = SystemAudioMeter.instance;
```

`SystemAudioMeter.instance` resolves to the active platform implementation through the package platform interface.

## Core class

```dart
abstract class SystemAudioMeter {
  static SystemAudioMeter get instance;

  Stream<AudioLevels> get levels;
  Stream<AudioLevels> get inputLevels;
  Stream<AudioDeviceEvent> get deviceEvents;

  Future<List<AudioOutputDevice>> getOutputDevices();
  Future<List<AudioInputDevice>> getInputDevices();

  Future<void> setOutputDevice(String? deviceId);
  Future<void> setInputDevice(String? deviceId);

  Future<AudioOutputDevice?> getCurrentOutputDevice();
  Future<AudioInputDevice?> getCurrentInputDevice();

  Future<void> start();
  Future<void> startInput();

  Future<void> stop();
  Future<void> stopInput();

  Future<bool> get isRunning;
  Future<bool> get isInputRunning;
}
```

## Streams

### `levels`

Output stereo meter stream.

```dart
meter.levels.listen((AudioLevels levels) {
  print(levels.leftPeak);
  print(levels.rightPeak);
});
```

### `inputLevels`

Input stereo meter stream for microphone-like devices.

```dart
meter.inputLevels.listen((AudioLevels levels) {
  print(levels.inputDeviceName);
});
```

### `deviceEvents`

Connection and disconnection stream for device-aware UIs.

```dart
meter.deviceEvents.listen((AudioDeviceEvent event) {
  print('${event.flow} ${event.kind}');
});
```

## Device management

### List devices

```dart
final outputs = await meter.getOutputDevices();
final inputs = await meter.getInputDevices();
```

### Select devices

```dart
await meter.setOutputDevice(outputId);
await meter.setInputDevice(inputId);
```

Pass `null` to return to the system default:

```dart
await meter.setOutputDevice(null);
await meter.setInputDevice(null);
```

### Query current devices

```dart
final currentOutput = await meter.getCurrentOutputDevice();
final currentInput = await meter.getCurrentInputDevice();
```

## Meter lifecycle

### Start and stop output metering

```dart
await meter.start();
await meter.stop();
```

### Start and stop input metering

```dart
await meter.startInput();
await meter.stopInput();
```

### Running state

```dart
final outputRunning = await meter.isRunning;
final inputRunning = await meter.isInputRunning;
```

## Data models

### `AudioLevels`

Represents one meter event payload.

```dart
class AudioLevels {
  final double leftPeak;
  final double rightPeak;
  final DateTime timestamp;
  final String? outputDeviceId;
  final String? outputDeviceName;
  final String? inputDeviceId;
  final String? inputDeviceName;
}
```

Notes:

- values are normalized to `0.0..1.0`
- values are clamped before reaching Dart
- timestamps are emitted in milliseconds since epoch and converted to `DateTime`

### `AudioOutputDevice`

```dart
class AudioOutputDevice {
  final String id;
  final String name;
  final bool isDefault;
}
```

### `AudioInputDevice`

```dart
class AudioInputDevice {
  final String id;
  final String name;
  final bool isDefault;
}
```

### `AudioDeviceEvent`

```dart
enum AudioDeviceEventKind {
  connected,
  disconnected,
}

enum AudioDeviceFlow {
  output,
  input,
}

class AudioDeviceEvent {
  final AudioDeviceEventKind kind;
  final AudioDeviceFlow flow;
  final DateTime timestamp;
  final String? deviceId;
  final String? deviceName;
  final bool isDefault;
  final bool isSelected;
}
```

## Error handling

Errors are surfaced through platform channels and may appear:

- when a device cannot be opened
- when required permissions are missing
- when the active device disappears
- when macOS system audio capture is not authorized

Recommended pattern:

```dart
meter.inputLevels.listen(
  (levels) {
    // update UI
  },
  onError: (error) {
    debugPrint('Input metering error: $error');
  },
);
```

## API design notes

The API is intentionally small and UI-focused:

- it exposes peak levels, not raw PCM
- it favors live streams over retained audio data
- it supports device-aware desktop apps without expanding into recording features
