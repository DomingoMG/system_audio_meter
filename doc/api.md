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

  Stream<AudioLevels> get outputLevels;
  Stream<AudioLevels> get levels;
  Stream<AudioLevels> get inputLevels;
  Stream<AudioDeviceEvent> get deviceEvents;
  Stream<AudioSilenceEvent> get silenceEvents;

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

  Future<void> enableSilenceDetection({
    required AudioDeviceFlow flow,
    required double threshold,
    required Duration duration,
  });

  Future<void> disableSilenceDetection({
    required AudioDeviceFlow flow,
  });

  Future<bool> get isRunning;
  Future<bool> get isInputRunning;
}
```

## Streams

### `outputLevels`

Output stereo meter stream.

```dart
meter.outputLevels.listen((AudioLevels levels) {
  print(levels.leftPeak);
  print(levels.rightPeak);
});
```

### `levels`

Backward-compatible alias for `outputLevels`.

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

### `silenceEvents`

Optional output-silence transition stream.

```dart
meter.silenceEvents.listen((AudioSilenceEvent event) {
  print('${event.flow} ${event.type} at ${event.peakLevel}');
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

## Silence detection

Enable silence detection for system output:

```dart
await meter.enableSilenceDetection(
  flow: AudioDeviceFlow.output,
  threshold: 0.05,
  duration: const Duration(milliseconds: 800),
);

await meter.enableSilenceDetection(
  flow: AudioDeviceFlow.input,
  threshold: 0.05,
  duration: const Duration(milliseconds: 800),
);
```

Disable it again when no longer needed:

```dart
await meter.disableSilenceDetection(flow: AudioDeviceFlow.output);
await meter.disableSilenceDetection(flow: AudioDeviceFlow.input);
```

## Silence stage tracking

For UI-level severity escalation, use `AudioSilenceTracker` on top of the native silence events:

```dart
final tracker = meter.createSilenceTracker(
  stages: const <AudioSilenceStage>[
    AudioSilenceStage(
      id: 'warning',
      after: Duration(seconds: 5),
      severity: 'warning',
      label: 'Warning',
    ),
    AudioSilenceStage(
      id: 'critical',
      after: Duration(seconds: 10),
      severity: 'critical',
      label: 'Critical',
    ),
  ],
);
```

Listen for derived state changes:

```dart
tracker.states.listen((AudioSilenceState state) {
  print(state.flow);
  print(state.type);
  print(state.silentFor);
  print(state.currentStage?.severity);
});
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

### `AudioSilenceEvent`

```dart
enum AudioSilenceEventType {
  silenceStarted,
  silenceEnded,
}

class AudioSilenceEvent {
  final AudioSilenceEventType type;
  final AudioDeviceFlow flow;
  final double peakLevel;
  final DateTime timestamp;
  final String? deviceId;
  final String? deviceName;
}
```

### `AudioSilenceStage`

```dart
class AudioSilenceStage {
  final String id;
  final Duration after;
  final String? severity;
  final String? label;
}
```

### `AudioSilenceState`

```dart
enum AudioSilenceStateType {
  active,
  silent,
  stageChanged,
}

class AudioSilenceState {
  final AudioSilenceStateType type;
  final AudioDeviceFlow flow;
  final bool isSilent;
  final Duration silentFor;
  final DateTime updatedAt;
  final AudioSilenceStage? currentStage;
  final String? deviceId;
  final String? deviceName;
  final double peakLevel;
  final AudioSilenceEventType? sourceEventType;
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
