# Troubleshooting

This page covers the most common integration and runtime issues.

## No output values on macOS

### Symptoms

- `start()` succeeds
- the output meter stays at `0`
- no crash is visible

### Checks

1. Confirm you are running on macOS `14.2+`.
2. Confirm your app includes `NSAudioCaptureUsageDescription`.
3. Confirm macOS granted system audio capture access.
4. Restart the app after changing privacy settings.

### Notes

On macOS, output metering depends on Core Audio taps and runtime authorization. Missing permission may appear as silence.

## No input values on macOS

### Symptoms

- `startInput()` appears to work
- the microphone meter never moves

### Checks

1. Confirm your app includes `NSMicrophoneUsageDescription`.
2. If App Sandbox is enabled, add:

```xml
<key>com.apple.security.device.audio-input</key>
<true/>
```

3. Open `System Settings > Privacy & Security > Microphone`.
4. Ensure your app is enabled there.
5. Fully restart the app after changing permissions.

### Why this happens

Apple documents that without microphone permission the app may receive silence instead of usable input data.

## Device disappeared while metering

### Symptoms

- stream errors
- values reset to `0`
- selected device is gone

### What to do

- listen to `deviceEvents`
- refresh device lists
- allow the user to reselect a device
- optionally auto-resume if the same device returns

## A selected device does not reconnect cleanly

The operating system may recreate devices with a new identifier. The plugin may recover by friendly-name matching, but this is not guaranteed for every virtual or Bluetooth device.

## Linux is not working

Linux support is not implemented in the current release. The plugin currently exposes a stub backend there.

## `flutter pub publish` fails on metadata

Common causes:

- too many `topics`
- modified tracked files
- invalid screenshot references
- stale package version

Run:

```bash
flutter pub publish --dry-run
```

before publishing.

## The app compiles but meter data seems wrong

Check:

- selected device is the one you expect
- Flutter UI is subscribed before starting the meter
- your UI is not accidentally displaying stale state
- the platform is supported for the selected feature

## Getting more diagnostic data

Useful approaches:

- log `deviceEvents`
- print current selected device names and IDs
- print `isRunning` and `isInputRunning`
- verify permission prompts were accepted

Example:

```dart
debugPrint('Output running: ${await meter.isRunning}');
debugPrint('Input running: ${await meter.isInputRunning}');
```
