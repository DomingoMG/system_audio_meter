# FAQ

## Does this plugin record audio?

No. It does not record audio.

## Does it keep raw PCM buffers?

No. It processes the current native buffer in memory and releases it immediately after peak calculation.

## Does it generate FFT data?

No. FFT generation is out of scope.

## Does it generate waveforms?

No. Waveform generation is not implemented.

## Can I use it for audio analysis?

Only for lightweight real-time peak visualization. It is not intended for advanced analysis pipelines.

## Why are the values normalized?

The plugin is designed for UI meters, so it emits compact normalized values in the `0.0..1.0` range.

## Why is macOS output metering limited to macOS 14.2+?

The output backend depends on Core Audio process taps, which are required for the current supported implementation.

## Why is macOS not implemented the same way as Windows?

Windows uses WASAPI loopback. macOS does not expose the same loopback model for system output metering, so the plugin uses Core Audio taps plus a private aggregate device instead.

## Why do I get silence on macOS input metering?

Common causes:

- microphone permission was denied
- `NSMicrophoneUsageDescription` is missing
- sandboxed app is missing `com.apple.security.device.audio-input`

See [Troubleshooting](troubleshooting.md).

## Can I monitor device connection changes?

Yes. Use `deviceEvents`.

## Does Linux work today?

Not yet. Linux support is planned but not implemented in the current release.

## Is Bluetooth supported?

It can work, but behavior depends on the operating system and the device. Recreated endpoints or device-mode changes can affect identity and reconnect behavior.

## Can I build a recorder on top of this plugin?

Not directly. The plugin intentionally does not expose raw audio buffers or recording APIs.
