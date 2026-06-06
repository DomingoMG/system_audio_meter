import 'package:flutter/material.dart';
import 'package:system_audio_meter/system_audio_meter.dart';

class SilenceStatusCard extends StatelessWidget {
  const SilenceStatusCard({super.key, 
    required this.enabled,
    required this.isSilent,
    required this.title,
    this.stage,
    required this.threshold,
    required this.duration,
    required this.statusMessage,
  });

  final bool enabled;
  final bool isSilent;
  final String title;
  final AudioSilenceStage? stage;
  final double threshold;
  final Duration duration;
  final String? statusMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color foreground = isSilent
        ? const Color(0xFF92400E)
        : const Color(0xFF166534);
    final Color background = isSilent
        ? const Color(0xFFFEF3C7)
        : const Color(0xFFDCFCE7);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: enabled ? background : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                isSilent ? Icons.volume_off_rounded : Icons.graphic_eq_rounded,
                color: enabled ? foreground : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                enabled ? title : 'Silence detection unavailable',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: enabled ? foreground : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Threshold: ${(threshold * 100).toStringAsFixed(0)}%  •  Duration: ${duration.inMilliseconds} ms',
          ),
          if (stage != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              'Current stage: ${stage?.label ?? stage?.id}${stage?.severity == null ? '' : ' (${stage!.severity})'}',
            ),
          ],
          if (statusMessage != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(statusMessage!),
          ],
        ],
      ),
    );
  }
}
