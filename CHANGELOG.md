## 0.3.0

- Added macOS output metering using Core Audio taps and a private aggregate device.
- Added macOS input metering using CoreAudio device capture.
- Added macOS device connect/disconnect monitoring and active-meter reattachment behavior.
- Added explicit microphone-permission handling for macOS input metering.
- Documented macOS 14.2+ requirements, privacy keys, and sandbox entitlements.

## 0.2.0

- Added `AudioDeviceEvent`, `AudioDeviceEventKind`, and `AudioDeviceFlow`.
- Added `deviceEvents` so Dart can listen for input/output connection and disconnection changes.
- Added automatic Windows reattachment logic for active input and output streams when devices return.
- Added selected-device recovery by friendly name when Windows recreates a device with a new `deviceId`.
- Added UI-side auto-refresh and auto-resume behavior in the example app for reconnectable devices.
- Improved disconnect handling so meters reset cleanly to `0 / 0` while waiting for reconnection.

## 0.1.1

- Added `AudioInputDevice` and input-device metadata on `AudioLevels`.
- Added input device listing, selection, and current-device queries to the Dart API.
- Added `inputLevels`, `startInput`, `stopInput`, and `isInputRunning`.
- Added Windows WASAPI input capture support alongside the existing output loopback path.
- Expanded the example app to demonstrate both output and input metering.

## 0.1.0

- Initial public release.
- Added the desktop `SystemAudioMeter.instance` API.
- Added `AudioLevels` and `AudioOutputDevice` models.
- Added `MethodChannel` and `EventChannel` integration for meter streaming.
- Added Windows WASAPI loopback support for real-time stereo peak levels.
- Added macOS system output metering with Core Audio taps and a private aggregate device.
- Added a safe unsupported stub for Linux.
- Added an example app, screenshot assets, and README documentation.
