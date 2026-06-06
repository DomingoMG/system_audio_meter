import 'audio_device_event.dart';
import 'audio_silence_event.dart';
import 'audio_silence_stage.dart';

enum AudioSilenceStateType {
  active,
  silent,
  stageChanged,
}

class AudioSilenceState {
  const AudioSilenceState({
    required this.type,
    required this.flow,
    required this.isSilent,
    required this.silentFor,
    required this.updatedAt,
    this.currentStage,
    this.deviceId,
    this.deviceName,
    this.peakLevel = 0.0,
    this.sourceEventType,
  });

  final AudioSilenceStateType type;
  final AudioDeviceFlow flow;
  final bool isSilent;
  final Duration silentFor;
  final DateTime updatedAt;
  final AudioSilenceStage? currentStage;
  final String? deviceId;
  final String? deviceName;
  final double peakLevel;
  final AudioSilenceEventType? sourceEventType;
}
