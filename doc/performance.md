# Performance

`system_audio_meter` is optimized for **real-time visualization**, not deep audio analysis.

## Performance model

The plugin processes only the current native audio buffer required to compute peak levels.

It does not:

- write audio to disk
- hold rolling PCM history
- allocate large analysis windows
- compute FFT bins
- generate waveform arrays

This keeps CPU, memory, and Dart bridge traffic relatively low for desktop UI scenarios.

## Data flow efficiency

### Native side

- reads a native audio buffer already provided by the operating system
- scans samples for peak amplitude
- emits a compact payload with only the data Flutter needs

### Dart side

- receives normalized values
- updates the UI directly
- avoids any expensive audio-side decoding work

## Event payload size

Each meter update is intentionally small:

```json
{
  "leftPeak": 0.42,
  "rightPeak": 0.38,
  "timestamp": 1710000000000,
  "outputDeviceId": "...",
  "outputDeviceName": "Speakers / Headphones"
}
```

For input metering, the payload uses `inputDeviceId` and `inputDeviceName`.

## Memory management

The plugin is designed to avoid memory growth under steady use.

### Important guarantees

- Audio is processed only in memory.
- Audio buffers are not retained after use.
- Buffers are released immediately after the meter values are calculated.
- No background PCM archive is maintained.
- No sample history ring buffer is exposed to Flutter.

## Why this matters

That design keeps the plugin suitable for:

- always-on desktop widgets
- tray utilities
- dashboards
- embedded metering views

without turning it into a recorder or analysis engine.

## UI performance guidance

Even though the plugin is lightweight, UI performance still depends on how often your widget tree rebuilds.

Recommended practices:

- keep metering widgets isolated from unrelated layout
- avoid rebuilding large pages on each meter event
- use lightweight visual components for progress bars or custom painters
- debounce or smooth values in Dart only if your UI needs it

## Platform-specific notes

### Windows

- WASAPI is efficient for the loopback and input capture paths used here
- reconnect handling adds some lifecycle complexity but not significant steady-state cost

### macOS

- output metering relies on Core Audio taps and a private aggregate device
- input metering depends on CoreAudio device callbacks
- permission failures may appear as silence rather than high CPU usage

## What this plugin is not optimized for

Use a different toolchain if you need:

- waveform rendering over time
- spectrum visualization
- file recording
- offline audio processing
- audio editing
- detailed acoustic analysis

Those workloads require different memory and compute tradeoffs than this plugin intentionally makes.
