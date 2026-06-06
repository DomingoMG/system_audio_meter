class AudioSilenceStage {
  const AudioSilenceStage({
    required this.id,
    required this.after,
    this.severity,
    this.label,
  });

  final String id;
  final Duration after;
  final String? severity;
  final String? label;
}
