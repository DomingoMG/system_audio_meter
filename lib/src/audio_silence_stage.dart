/// One configurable silence escalation step used by [AudioSilenceTracker].
///
/// A stage becomes active after the monitored flow has remained silent for at
/// least [after].
class AudioSilenceStage {
  const AudioSilenceStage({
    required this.id,
    required this.after,
    this.severity,
    this.label,
  });

  /// Stable identifier for this stage.
  final String id;

  /// Silence duration required before this stage becomes active.
  final Duration after;

  /// Optional severity string chosen by the host application.
  final String? severity;

  /// Optional user-facing label for UI rendering.
  final String? label;
}
