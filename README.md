# system_audio_meter

[![Documentation](https://img.shields.io/badge/docs-GitHub%20Pages-0A7EA4)](https://domingomg.github.io/system_audio_meter/)

A Flutter desktop plugin for real-time system audio metering on Windows and macOS.

`system_audio_meter` captures live peak levels from the operating system audio pipeline and exposes them to Flutter through streams that are easy to bind to VU meters, peak bars, diagnostics overlays, and device-monitoring UIs.

## Official documentation

The full documentation website for this repository is available at:

- [domingomg.github.io/system_audio_meter](https://domingomg.github.io/system_audio_meter/)

Use the documentation site for:

- installation and platform setup
- macOS requirements and permissions
- API reference
- architecture diagrams
- performance and memory behavior
- troubleshooting and FAQ

## Key capabilities

- Real-time output metering for desktop audio
- Real-time input metering for microphones and other capture devices
- Output and input device enumeration
- Device selection and default-device fallback
- Device connection and disconnection events
- Automatic reconnection handling when supported by the platform

## Important scope

This plugin is intentionally designed for visualization, not for audio production workflows.

- It does **not** record audio
- It does **not** persist raw audio buffers
- It does **not** generate FFT data
- It does **not** generate waveforms
- It processes audio in memory only
- It releases native buffers immediately after peak extraction

## Platform support

| Platform | Status | Notes |
| --- | --- | --- |
| Windows | Supported | Uses WASAPI loopback for output and shared capture for input |
| macOS | Supported | Uses Core Audio taps for output and CoreAudio input capture; requires macOS 14.2+ for output metering |
| Linux | Pending | Planned for a future release |

## Installation

Add the dependency:

```yaml
dependencies:
  system_audio_meter: ^0.3.1
```

Or use:

```bash
flutter pub add system_audio_meter
```

## Quick start

```dart
final meter = SystemAudioMeter.instance;

final outputSubscription = meter.levels.listen((AudioLevels levels) {
  print('Output L: ${levels.leftPeak}, R: ${levels.rightPeak}');
});

final inputSubscription = meter.inputLevels.listen((AudioLevels levels) {
  print('Input L: ${levels.leftPeak}, R: ${levels.rightPeak}');
});

await meter.start();
await meter.startInput();
```

Stop the streams when they are no longer needed:

```dart
await SystemAudioMeter.instance.stop();
await SystemAudioMeter.instance.stopInput();
await outputSubscription.cancel();
await inputSubscription.cancel();
```

## Screenshots

### Windows

![System Audio Meter on Windows](doc/assets/images/screenshot_windows.jpeg)

### macOS

![System Audio Meter on macOS](doc/assets/images/screenshot_macos.png)

## macOS host app requirements

If your Flutter app uses this plugin on macOS, review the full setup guide in the official docs. At minimum, host applications must declare the appropriate privacy keys, and sandboxed apps also need the correct audio-input entitlement for microphone metering.

Documentation:

- [Installation guide](https://domingomg.github.io/system_audio_meter/installation/)
- [Troubleshooting guide](https://domingomg.github.io/system_audio_meter/troubleshooting/)

## Repository

- [GitHub repository](https://github.com/DomingoMG/system_audio_meter)
- [Package on pub.dev](https://pub.dev/packages/system_audio_meter)
