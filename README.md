# system_audio_meter

A desktop-only Flutter plugin for visualizing real-time desktop audio levels.

It exposes normalized stereo peak values through `EventChannel`s, reports device connection lifecycle events, keeps processing in memory only, and is designed for lightweight UI meters rather than recording or audio analysis pipelines.

![System Audio Meter example](screenshots/screenshot_01.jpeg)

## Highlights

- Small public API centered on `SystemAudioMeter.instance`
- `Stream<AudioLevels>` for real-time left/right peak updates
- `Stream<AudioDeviceEvent>` for device connection/disconnection changes
- Output device listing and selection support
- Input device listing and selection support
- Windows implementation based on **WASAPI loopback capture** for output and shared-mode capture for input
- Automatic reconnect handling for active meters on Windows
- No recording, no file output, no raw buffer persistence
- Safe unsupported stubs for macOS and Linux while native backends are still pending

## Platform status

| Platform | Status | Notes |
| --- | --- | --- |
| Windows | Implemented | Uses WASAPI loopback on the selected/default render device and WASAPI capture on the selected/default input device |
| macOS | Stub | Returns a safe unsupported error for live metering |
| Linux | Stub | Returns a safe unsupported error until a PulseAudio/PipeWire backend is added |

## Installation

Add the package to your Flutter desktop app:

```yaml
dependencies:
  system_audio_meter: ^0.2.0
```

Or install it directly from the command line:

```bash
flutter pub add system_audio_meter
```

## Quick start

```dart
final meter = SystemAudioMeter.instance;

final subscription = meter.levels.listen((AudioLevels levels) {
  print('L: ${levels.leftPeak}, R: ${levels.rightPeak}');
});

await meter.start();

final inputSubscription = meter.inputLevels.listen((AudioLevels levels) {
  print('Mic L: ${levels.leftPeak}, Mic R: ${levels.rightPeak}');
});

await meter.startInput();

final deviceEvents = meter.deviceEvents.listen((AudioDeviceEvent event) {
  print('${event.flow} ${event.kind} ${event.deviceName}');
});
```

Stop when you no longer need updates:

```dart
await SystemAudioMeter.instance.stop();
await SystemAudioMeter.instance.stopInput();
await subscription.cancel();
await inputSubscription.cancel();
await deviceEvents.cancel();
```

## Public API

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

### AudioDeviceEvent

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
    this.inputDeviceId,
    this.inputDeviceName,
  });

  final double leftPeak;
  final double rightPeak;
  final DateTime timestamp;
  final String? outputDeviceId;
  final String? outputDeviceName;
  final String? inputDeviceId;
  final String? inputDeviceName;
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

### AudioInputDevice

```dart
class AudioInputDevice {
  const AudioInputDevice({
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

```dart
final inputDevices = await SystemAudioMeter.instance.getInputDevices();

final selectedInput = inputDevices.firstWhere((device) => device.isDefault);

await SystemAudioMeter.instance.setInputDevice(selectedInput.id);
await SystemAudioMeter.instance.startInput();
```

Behavior:

- `setOutputDevice(null)` switches back to the system default output device
- `setInputDevice(null)` switches back to the system default input device
- On Windows, the plugin uses the default render device by default
- On Windows, the plugin uses the default capture device by default for input metering
- If a meter is actively running and the underlying Windows device disconnects, the plugin emits a disconnect event and resets levels to `0.0`
- If that device reconnects, Windows can automatically reattach the active meter when the device is still the selected target
- For explicitly selected devices, Windows reconnection can recover by `deviceId` first and then by friendly name if the OS recreated the endpoint

## Device lifecycle events

Use `deviceEvents` when you want Dart to react to connection changes without treating them as fatal stream failures:

```dart
final subscription = SystemAudioMeter.instance.deviceEvents.listen(
  (AudioDeviceEvent event) {
    if (event.flow == AudioDeviceFlow.input &&
        event.kind == AudioDeviceEventKind.connected) {
      print('Input device is back: ${event.deviceName}');
    }
  },
);
```

Typical uses:

- show connected/disconnected banners in the UI
- auto-resume a meter only if the user had already started it
- refresh device dropdowns when Windows recreates an endpoint with a new `deviceId`

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

For input metering, the payload uses `inputDeviceId` and `inputDeviceName` instead.

Notes:

- `leftPeak` and `rightPeak` are normalized to `0.0..1.0`
- values are clamped before reaching Dart
- updates are throttled for visualization rather than emitted per raw audio frame

Example device event payload:

```dart
{
  "kind": "connected",
  "flow": "input",
  "timestamp": 1710000000000,
  "deviceId": "...",
  "deviceName": "USB Microphone",
  "isDefault": false,
  "isSelected": true
}
```

## Example app

The example app included in this repository demonstrates:

- starting the meter
- stopping the meter
- refreshing output devices
- selecting an output device
- refreshing input devices
- selecting an input device
- reacting to device connect/disconnect events
- auto-resuming a previously active meter after reconnection
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

- Implemented for desktop metering with WASAPI loopback for output and WASAPI capture for input
- Includes Windows device lifecycle monitoring and automatic reattachment for active meters
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
