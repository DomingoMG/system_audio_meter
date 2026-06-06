# Installation

This page covers package installation and platform-specific setup requirements.

## Add the package

```yaml
dependencies:
  system_audio_meter: ^0.4.1
```

Then:

```bash
flutter pub get
```

## Supported targets

- Windows desktop
- macOS desktop

Linux support is not implemented yet.

## Windows setup

No extra manifest or entitlement changes are required for the plugin itself.

Typical run command:

```bash
flutter run -d windows
```

## macOS setup

macOS support requires **macOS 14.2 or newer** for system output metering.

### Why macOS 14.2+

The output metering backend depends on Core Audio process taps:

- `AudioHardwareCreateProcessTap`
- private aggregate devices for tap routing

Those APIs are not available on older macOS versions in a way that supports the current architecture.

### Required `Info.plist` keys

Add the following to your macOS app `Info.plist`:

```xml
<key>NSAudioCaptureUsageDescription</key>
<string>This app needs system audio capture access to display real-time output meter levels.</string>

<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access to display real-time input meter levels.</string>
```

Use:

- `NSAudioCaptureUsageDescription` for output metering
- `NSMicrophoneUsageDescription` for input metering

Without the required privacy declarations, the app may fail authorization or receive silence.

### App Sandbox entitlement

If your macOS app uses App Sandbox, add:

```xml
<key>com.apple.security.device.audio-input</key>
<true/>
```

This entitlement is required for microphone input metering in sandboxed apps.

### Example file locations

In the example app bundled with this repository, the setup lives in:

- `example/macos/Runner/Info.plist`
- `example/macos/Runner/DebugProfile.entitlements`
- `example/macos/Runner/Release.entitlements`

### Run on macOS

```bash
flutter run -d macos
```

## Verify installation

Use the included example app or a quick smoke test:

```dart
final meter = SystemAudioMeter.instance;
final devices = await meter.getOutputDevices();
debugPrint('Output devices: ${devices.length}');
```

## Pub.dev publishing note

If you are maintaining a downstream app rather than this plugin, no MkDocs or documentation setup is required. The MkDocs site included in this repository is only for project documentation.
