# Roadmap

This roadmap reflects the intended direction of the project, not a fixed delivery contract.

## Current release focus

- Stable Windows output metering
- Stable Windows input metering
- Native macOS output metering
- Native macOS input metering
- Device lifecycle events
- Reconnect-aware metering behavior

## Near-term priorities

- Improve macOS documentation and integration guidance
- Expand automated integration coverage for desktop platforms
- Harden reconnect behavior across more device types
- Improve example app diagnostics for permissions and platform failures

## Planned Linux support

Linux support is intentionally deferred for now.

The likely direction is:

- PulseAudio support
- PipeWire support
- desktop-oriented device enumeration
- parity with the existing Flutter API when feasible

## Possible future enhancements

- richer diagnostics for permission and device errors
- optional smoothing helpers on the Dart side
- more sample apps
- release automation and docs deployment

## Non-goals

The project is not planning to become:

- a recorder
- an audio editor
- a waveform generator
- an FFT analyzer
- a DAW-style processing framework

The core goal remains:

**fast, lightweight, real-time desktop audio visualization for Flutter**
