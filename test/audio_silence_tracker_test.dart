import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:system_audio_meter/system_audio_meter.dart';

void main() {
  test('tracker emits silence start, stage changes, and active reset', () async {
    final controller = StreamController<AudioSilenceEvent>.broadcast();
    final tracker = AudioSilenceTracker(
      events: controller.stream,
      stages: const <AudioSilenceStage>[
        AudioSilenceStage(
          id: 'warning',
          after: Duration(milliseconds: 20),
          severity: 'warning',
        ),
        AudioSilenceStage(
          id: 'critical',
          after: Duration(milliseconds: 40),
          severity: 'critical',
        ),
      ],
    );
    addTearDown(() async {
      tracker.dispose();
      await controller.close();
    });

    final emitted = <AudioSilenceState>[];
    final subscription = tracker.states.listen(emitted.add);
    addTearDown(subscription.cancel);

    controller.add(
      AudioSilenceEvent(
        type: AudioSilenceEventType.silenceStarted,
        flow: AudioDeviceFlow.output,
        peakLevel: 0.01,
        timestamp: DateTime.now(),
        deviceId: 'out-1',
        deviceName: 'Speakers',
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 55));

    expect(emitted.length, greaterThanOrEqualTo(3));
    expect(emitted[0].type, AudioSilenceStateType.silent);
    expect(emitted[0].flow, AudioDeviceFlow.output);
    expect(emitted[1].type, AudioSilenceStateType.stageChanged);
    expect(emitted[1].currentStage?.id, 'warning');
    expect(emitted[2].type, AudioSilenceStateType.stageChanged);
    expect(emitted[2].currentStage?.id, 'critical');

    controller.add(
      AudioSilenceEvent(
        type: AudioSilenceEventType.silenceEnded,
        flow: AudioDeviceFlow.output,
        peakLevel: 0.3,
        timestamp: DateTime.now(),
        deviceId: 'out-1',
        deviceName: 'Speakers',
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(emitted.last.type, AudioSilenceStateType.active);
    expect(emitted.last.isSilent, isFalse);
    expect(emitted.last.currentStage?.id, 'critical');
  });

  test('tracker keeps input and output stage progression independent', () async {
    final controller = StreamController<AudioSilenceEvent>.broadcast();
    final tracker = AudioSilenceTracker(
      events: controller.stream,
      stages: const <AudioSilenceStage>[
        AudioSilenceStage(
          id: 'warning',
          after: Duration(milliseconds: 25),
          severity: 'warning',
        ),
      ],
    );
    addTearDown(() async {
      tracker.dispose();
      await controller.close();
    });

    final emitted = <AudioSilenceState>[];
    final subscription = tracker.states.listen(emitted.add);
    addTearDown(subscription.cancel);

    controller.add(
      AudioSilenceEvent(
        type: AudioSilenceEventType.silenceStarted,
        flow: AudioDeviceFlow.output,
        peakLevel: 0.0,
        timestamp: DateTime.now(),
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));

    controller.add(
      AudioSilenceEvent(
        type: AudioSilenceEventType.silenceStarted,
        flow: AudioDeviceFlow.input,
        peakLevel: 0.0,
        timestamp: DateTime.now(),
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 35));

    final outputWarning = emitted.where(
      (state) =>
          state.flow == AudioDeviceFlow.output &&
          state.currentStage?.id == 'warning',
    );
    final inputWarning = emitted.where(
      (state) =>
          state.flow == AudioDeviceFlow.input &&
          state.currentStage?.id == 'warning',
    );

    expect(outputWarning.length, 1);
    expect(inputWarning.length, 1);
  });

  test('tracker reset stops stage escalation after a manual stop', () async {
    final controller = StreamController<AudioSilenceEvent>.broadcast();
    final tracker = AudioSilenceTracker(
      events: controller.stream,
      stages: const <AudioSilenceStage>[
        AudioSilenceStage(
          id: 'warning',
          after: Duration(milliseconds: 30),
          severity: 'warning',
        ),
      ],
    );
    addTearDown(() async {
      tracker.dispose();
      await controller.close();
    });

    final emitted = <AudioSilenceState>[];
    final subscription = tracker.states.listen(emitted.add);
    addTearDown(subscription.cancel);

    controller.add(
      AudioSilenceEvent(
        type: AudioSilenceEventType.silenceStarted,
        flow: AudioDeviceFlow.output,
        peakLevel: 0.0,
        timestamp: DateTime.now(),
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));
    tracker.reset(flow: AudioDeviceFlow.output);
    await Future<void>.delayed(const Duration(milliseconds: 35));

    final warningStates = emitted.where(
      (state) =>
          state.flow == AudioDeviceFlow.output &&
          state.type == AudioSilenceStateType.stageChanged,
    );

    expect(warningStates, isEmpty);
    expect(emitted.last.flow, AudioDeviceFlow.output);
    expect(emitted.last.type, AudioSilenceStateType.active);
    expect(emitted.last.isSilent, isFalse);
  });
}
