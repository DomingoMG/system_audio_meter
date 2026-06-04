# system_audio_meter

A desktop-only Flutter plugin for visualizing real-time **system output audio levels**.

It exposes normalized stereo peak values through an `EventChannel`, keeps processing in memory only, and is designed for lightweight UI meters rather than recording or audio analysis pipelines.

![System Audio Meter example](screenshots/screenshot_01.jpeg)

## Highlights

- Small public API centered on `SystemAudioMeter.instance`
- `Stream<AudioLevels>` for real-time left/right peak updates
- Output device listing and selection support
- Windows implementation based on **WASAPI loopback capture**
- No recording, no file output, no raw buffer persistence
- Safe unsupported stubs for macOS and Linux while native backends are still pending

## Platform status

| Platform | Status | Notes |
| --- | --- | --- |
| Windows | Implemented | Uses WASAPI loopback on the selected or default render device |
| macOS | Stub | Returns a safe unsupported error for live metering |
| Linux | Stub | Returns a safe unsupported error until a PulseAudio/PipeWire backend is added |

## Installation

Add the package to your Flutter desktop app:

```yaml
dependencies:
  system_audio_meter:
    path: ../system_audio_meter
```

Then run:

```bash
flutter pub get
```

## Quick start

```dart
final meter = SystemAudioMeter.instance;

final subscription = meter.levels.listen((AudioLevels levels) {
  print('L: ${levels.leftPeak}, R: ${levels.rightPeak}');
});

await meter.start();
```

Stop when you no longer need updates:

```dart
await SystemAudioMeter.instance.stop();
await subscription.cancel();
```

## Public API

```dart
abstract class SystemAudioMeter {
  static SystemAudioMeter get instance;

  Stream<AudioLevels> get levels;

  Future<List<AudioOutputDevice>> getOutputDevices();

  Future<void> setOutputDevice(String? deviceId);

  Future<AudioOutputDevice?> getCurrentOutputDevice();

  Future<void> start();

  Future<void> stop();

  Future<bool> get isRunning;
}
```

### AudioLevels

```dart
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
}
```

### AudioOutputDevice

```dart
class AudioOutputDevice {
  const AudioOutputDevice({
    required this.id,
    required this.name,
    required this.isDefault,
  });

  final String id;
  final String name;
  final bool isDefault;
}
```

## Device selection

```dart
final devices = await SystemAudioMeter.instance.getOutputDevices();

final selectedDevice = devices.firstWhere((device) => device.isDefault);

await SystemAudioMeter.instance.setOutputDevice(selectedDevice.id);
await SystemAudioMeter.instance.start();
```

Behavior:

- `setOutputDevice(null)` switches back to the system default output device
- On Windows, the plugin uses the default render device by default
- If a selected device cannot be opened, the implementation attempts to fall back safely when possible
- If capture fails while streaming, the stream emits a platform error instead of crashing the app

## Event payload

Each event is intentionally small and UI-focused:

```dart
{
  "leftPeak": 0.42,
  "rightPeak": 0.38,
  "timestamp": 1710000000000,
  "outputDeviceId": "...",
  "outputDeviceName": "Speakers / Headphones"
}
```

Notes:

- `leftPeak` and `rightPeak` are normalized to `0.0..1.0`
- values are clamped before reaching Dart
- updates are throttled for visualization rather than emitted per raw audio frame

## Example app

The example app included in this repository demonstrates:

- starting the meter
- stopping the meter
- refreshing output devices
- selecting an output device
- rendering left/right visual level bars

Run it with:

```bash
cd example
flutter run -d windows
```

## Design constraints

This plugin is intentionally limited in scope:

- no recording
- no saved audio
- no raw sample history
- no FFT
- no LUFS
- no waveform generation

The native side only processes the current audio buffer long enough to calculate meter values and then releases it.

## Current limitations

### Windows

- Implemented for desktop metering with WASAPI loopback
- The current focus is stability and safe lifecycle handling rather than advanced analysis

### macOS

- Live system-output metering is not implemented yet
- Reliable support may require more CoreAudio-specific work and, depending on the routing strategy, extra system configuration

### Linux

- Live system-output metering is not implemented yet
- A production-ready backend still needs to be built and validated for common Ubuntu PulseAudio and PipeWire setups

## Repository structure

```text
lib/        Dart API and channel bindings
windows/    Windows WASAPI implementation
macos/      macOS stub implementation
linux/      Linux stub implementation
example/    Example desktop app
screenshots/ README assets
```
