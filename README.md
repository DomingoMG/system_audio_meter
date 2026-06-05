# system_audio_meter

A desktop-only Flutter plugin for visualizing real-time desktop audio levels.

It exposes normalized stereo peak values through `EventChannel`s, reports device connection lifecycle events, keeps processing in memory only, and is designed for lightweight UI meters rather than recording or audio analysis pipelines.

## Screenshots

### Windows

![System Audio Meter on Windows](screenshots/screenshot_windows.jpeg)

### macOS

![System Audio Meter on macOS](screenshots/screenshot_macos.png)

## Highlights

- Small public API centered on `SystemAudioMeter.instance`
- `Stream<AudioLevels>` for real-time left/right peak updates
- `Stream<AudioDeviceEvent>` for device connection/disconnection changes
- Output device listing and selection support
- Input device listing and selection support
- Windows implementation based on **WASAPI loopback capture** for output and shared-mode capture for input
- macOS implementation based on **Core Audio taps** for output and **CoreAudio device input capture** for microphones
- Automatic reconnect handling for active meters on Windows
- Automatic reconnect handling for active meters on macOS when compatible devices return
- No recording, no file output, no raw buffer persistence
- Safe unsupported stub for Linux while the native backend is still pending

## Platform status

| Platform | Status | Notes |
| --- | --- | --- |
| Windows | Implemented | Uses WASAPI loopback on the selected/default render device and WASAPI capture on the selected/default input device |
| macOS | Implemented | Uses Core Audio taps for output, CoreAudio input capture for microphones, and device lifecycle listeners on macOS 14.2+ |
| Linux | Pending | PulseAudio/PipeWire support is planned for a future release |

## Installation

Add the package to your Flutter desktop app:

```yaml
dependencies:
  system_audio_meter: ^0.3.0
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
- On Windows and macOS, the plugin uses the default output device by default
- On Windows and macOS, the plugin uses the default input device by default when input metering is available
- If a meter is actively running and the underlying device disconnects, the plugin emits a disconnect event and resets levels to `0.0`
- If that device reconnects, the active meter can automatically reattach when the device is still the selected target
- For explicitly selected devices, reconnection recovery prefers `deviceId` and can fall back to friendly-name matching if the OS recreated the endpoint
- On macOS, the host app must declare the required privacy keys and entitlements before output or input values will work correctly

## macOS Requirements

macOS support is available for **macOS 14.2 or newer**.

Why 14.2:

- system output metering uses Core Audio process taps
- `AudioHardwareCreateProcessTap` is only available on macOS 14.2+
- the macOS backend cannot offer the Windows-style system-output loopback path on older releases

### Host app setup

To get real values on macOS, the host app must declare the correct privacy strings in its `Info.plist`:

```xml
<key>NSAudioCaptureUsageDescription</key>
<string>This app needs system audio capture access to display real-time output meter levels.</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access to display real-time input meter levels.</string>
```

If the macOS app uses App Sandbox, it must also enable microphone input in its entitlements:

```xml
<key>com.apple.security.device.audio-input</key>
<true/>
```

In the example app, those requirements are configured in:

- `example/macos/Runner/Info.plist`
- `example/macos/Runner/DebugProfile.entitlements`
- `example/macos/Runner/Release.entitlements`

### Runtime permissions

- output metering requires the user to allow system audio capture
- input metering requires the user to allow microphone access
- if the user denied either permission earlier, they may need to re-enable it in `System Settings > Privacy & Security`

### macOS limitations

- output metering is not implemented with the same mechanism as Windows; Windows uses WASAPI loopback while macOS uses Core Audio taps plus a private aggregate device
- output capture requires macOS 14.2+ and cannot be backported to older macOS versions with the same architecture
- input metering depends on microphone permission and, when sandboxing is enabled, the `com.apple.security.device.audio-input` entitlement
- device identity can still change when macOS recreates endpoints, so reconnection recovery may fall back from `deviceId` to friendly-name matching
- behavior can vary across virtual devices, aggregate devices created by third-party tools, and unusual multichannel hardware

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
- refresh device dropdowns when Windows or macOS recreate an endpoint with a new `deviceId`

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
flutter run -d macos
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

- Implemented with Core Audio taps for output and CoreAudio input capture for microphones
- Requires macOS 14.2 or newer
- Host apps must add `NSAudioCaptureUsageDescription`
- Host apps must add `NSMicrophoneUsageDescription` when using input metering
- Sandboxed macOS apps must enable `com.apple.security.device.audio-input` for microphone metering
- Output metering uses a private aggregate device internally and is not a 1:1 WASAPI loopback clone

### Linux

- Live system-output metering is not implemented yet
- A production-ready backend still needs to be built and validated for common Ubuntu PulseAudio and PipeWire setups

## Repository structure

```text
lib/        Dart API and channel bindings
windows/    Windows WASAPI implementation
macos/      macOS Core Audio implementation
linux/      Linux stub implementation
example/    Example desktop app
screenshots/ README assets
```
