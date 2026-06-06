# Getting Started

This guide walks through the fastest path to showing live audio meters in a Flutter desktop app.

## Prerequisites

- Flutter `3.19.0` or newer
- Dart `3.3.0` or newer
- A desktop Flutter app targeting Windows or macOS
- macOS `14.2+` if you want macOS output metering

## Add the dependency

```yaml
dependencies:
  system_audio_meter: ^0.3.0
```

Or:

```bash
flutter pub add system_audio_meter
```

## Minimal output metering example

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:system_audio_meter/system_audio_meter.dart';

class OutputMeterExample extends StatefulWidget {
  const OutputMeterExample({super.key});

  @override
  State<OutputMeterExample> createState() => _OutputMeterExampleState();
}

class _OutputMeterExampleState extends State<OutputMeterExample> {
  final SystemAudioMeter meter = SystemAudioMeter.instance;

  StreamSubscription<AudioLevels>? subscription;
  double left = 0;
  double right = 0;

  @override
  void initState() {
    super.initState();
    subscription = meter.outputLevels.listen((levels) {
      setState(() {
        left = levels.leftPeak;
        right = levels.rightPeak;
      });
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    meter.stop();
    super.dispose();
  }

  Future<void> start() => meter.start();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LinearProgressIndicator(value: left),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: right),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: start,
          child: const Text('Start output meter'),
        ),
      ],
    );
  }
}
```

## Minimal input metering example

```dart
final meter = SystemAudioMeter.instance;

final inputSubscription = meter.inputLevels.listen((AudioLevels levels) {
  debugPrint('Mic L: ${levels.leftPeak}, Mic R: ${levels.rightPeak}');
});

await meter.startInput();
```

## Listen for device changes

```dart
final deviceSubscription = SystemAudioMeter.instance.deviceEvents.listen(
  (AudioDeviceEvent event) {
    debugPrint('${event.flow} ${event.kind} ${event.deviceName}');
  },
);
```

## Recommended startup flow

1. Subscribe to `levels`, `inputLevels`, or both.
2. Subscribe to `deviceEvents` if your UI reacts to reconnects.
3. Query current devices with `getOutputDevices()` and `getInputDevices()`.
4. Let the user choose devices or use the default device.
5. Call `start()` and/or `startInput()`.

## Common next steps

- Add device dropdowns
- Persist selected device IDs in app settings
- Auto-resume active meters after reconnect events
- Display decibel-style UI labels on top of normalized `0.0..1.0` values

Continue with [Installation](installation.md) for platform-specific setup.
