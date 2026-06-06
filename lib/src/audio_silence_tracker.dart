import 'dart:async';

import 'audio_device_event.dart';
import 'audio_silence_event.dart';
import 'audio_silence_stage.dart';
import 'audio_silence_state.dart';

class AudioSilenceTracker {
  AudioSilenceTracker({
    required Stream<AudioSilenceEvent> events,
    required List<AudioSilenceStage> stages,
  })  : _stages = List<AudioSilenceStage>.unmodifiable(
          (List<AudioSilenceStage>.from(stages)
                ..sort((a, b) => a.after.compareTo(b.after)))
              .where((stage) => stage.after > Duration.zero),
        ) {
    _subscription = events.listen(_handleEvent);
  }

  final List<AudioSilenceStage> _stages;
  final StreamController<AudioSilenceState> _controller =
      StreamController<AudioSilenceState>.broadcast();
  final Map<AudioDeviceFlow, _FlowTrackerState> _states =
      <AudioDeviceFlow, _FlowTrackerState>{
    AudioDeviceFlow.output: _FlowTrackerState(),
    AudioDeviceFlow.input: _FlowTrackerState(),
  };

  late final StreamSubscription<AudioSilenceEvent> _subscription;

  Stream<AudioSilenceState> get states => _controller.stream;

  void reset({
    required AudioDeviceFlow flow,
    bool emitState = true,
  }) {
    final state = _states[flow]!;
    state.stageTimer?.cancel();
    state.stageTimer = null;
    final previousSilentFor = state.stopwatch.elapsed;
    state.stopwatch
      ..stop()
      ..reset();
    state.isSilent = false;
    state.currentStageIndex = -1;

    if (!emitState || _controller.isClosed) {
      return;
    }

    _controller.add(
      AudioSilenceState(
        type: AudioSilenceStateType.active,
        flow: flow,
        isSilent: false,
        silentFor: previousSilentFor,
        updatedAt: DateTime.now(),
        currentStage: null,
        deviceId: state.deviceId,
        deviceName: state.deviceName,
        peakLevel: state.peakLevel,
        sourceEventType: null,
      ),
    );
  }

  void resetAll({bool emitState = true}) {
    for (final flow in _states.keys) {
      reset(flow: flow, emitState: emitState);
    }
  }

  void dispose() {
    _subscription.cancel();
    for (final state in _states.values) {
      state.stageTimer?.cancel();
    }
    _controller.close();
  }

  void _handleEvent(AudioSilenceEvent event) {
    final state = _states[event.flow]!;
    state.deviceId = event.deviceId;
    state.deviceName = event.deviceName;
    state.peakLevel = event.peakLevel;

    if (event.type == AudioSilenceEventType.silenceStarted) {
      state.stageTimer?.cancel();
      state.stopwatch
        ..reset()
        ..start();
      state.isSilent = true;
      state.currentStageIndex = -1;
      _emitState(
        flow: event.flow,
        type: AudioSilenceStateType.silent,
        sourceEventType: event.type,
      );
      _scheduleNextStage(event.flow);
      return;
    }

    state.stageTimer?.cancel();
    final silentFor = state.stopwatch.elapsed;
    state.stopwatch
      ..stop()
      ..reset();
    state.isSilent = false;
    final currentStage = state.currentStageIndex >= 0 &&
            state.currentStageIndex < _stages.length
        ? _stages[state.currentStageIndex]
        : null;
    state.currentStageIndex = -1;

    _controller.add(
      AudioSilenceState(
        type: AudioSilenceStateType.active,
        flow: event.flow,
        isSilent: false,
        silentFor: silentFor,
        updatedAt: event.timestamp,
        currentStage: currentStage,
        deviceId: state.deviceId,
        deviceName: state.deviceName,
        peakLevel: event.peakLevel,
        sourceEventType: event.type,
      ),
    );
  }

  void _scheduleNextStage(AudioDeviceFlow flow) {
    final state = _states[flow]!;
    if (!state.isSilent) {
      return;
    }

    final nextIndex = state.currentStageIndex + 1;
    if (nextIndex >= _stages.length) {
      return;
    }

    final nextStage = _stages[nextIndex];
    final remaining = nextStage.after - state.stopwatch.elapsed;
    final delay = remaining.isNegative ? Duration.zero : remaining;

    state.stageTimer?.cancel();
    state.stageTimer = Timer(delay, () {
      if (_controller.isClosed) {
        return;
      }
      if (!state.isSilent) {
        return;
      }
      state.currentStageIndex = nextIndex;
      _emitState(
        flow: flow,
        type: AudioSilenceStateType.stageChanged,
        sourceEventType: AudioSilenceEventType.silenceStarted,
      );
      _scheduleNextStage(flow);
    });
  }

  void _emitState({
    required AudioDeviceFlow flow,
    required AudioSilenceStateType type,
    required AudioSilenceEventType sourceEventType,
  }) {
    final state = _states[flow]!;
    final currentStage = state.currentStageIndex >= 0 &&
            state.currentStageIndex < _stages.length
        ? _stages[state.currentStageIndex]
        : null;
    _controller.add(
      AudioSilenceState(
        type: type,
        flow: flow,
        isSilent: state.isSilent,
        silentFor: state.stopwatch.elapsed,
        updatedAt: DateTime.now(),
        currentStage: currentStage,
        deviceId: state.deviceId,
        deviceName: state.deviceName,
        peakLevel: state.peakLevel,
        sourceEventType: sourceEventType,
      ),
    );
  }
}

class _FlowTrackerState {
  final Stopwatch stopwatch = Stopwatch();
  Timer? stageTimer;
  bool isSilent = false;
  int currentStageIndex = -1;
  String? deviceId;
  String? deviceName;
  double peakLevel = 0.0;
}
