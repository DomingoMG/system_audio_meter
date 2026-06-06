
import 'package:flutter/material.dart';
import 'package:system_audio_meter_example/widgets/peak_meter.dart';

class DeviceOption {
  const DeviceOption({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;
}

class MeterSection extends StatelessWidget {
  const MeterSection({super.key, 
    required this.title,
    required this.isRunning,
    required this.statusMessage,
    required this.selectedId,
    required this.devices,
    required this.meterLeftLabel,
    required this.meterRightLabel,
    required this.leftPeak,
    required this.rightPeak,
    required this.accentColor,
    required this.secondaryColor,
    this.supplemental,
    required this.onStart,
    required this.onStop,
    required this.onRefresh,
    required this.onSelectDevice,
  });

  final String title;
  final bool isRunning;
  final String? statusMessage;
  final String? selectedId;
  final List<DeviceOption> devices;
  final String meterLeftLabel;
  final String meterRightLabel;
  final double leftPeak;
  final double rightPeak;
  final Color accentColor;
  final Color secondaryColor;
  final Widget? supplemental;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;
  final Future<void> Function() onRefresh;
  final ValueChanged<String?> onSelectDevice;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(isRunning ? 'Running' : 'Idle'),
            if (statusMessage != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(statusMessage!),
            ],
            if (supplemental != null) ...<Widget>[
              const SizedBox(height: 16),
              supplemental!,
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: onStart,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start meter'),
                ),
                OutlinedButton.icon(
                  onPressed: onStop,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop meter'),
                ),
                TextButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh devices'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String?>(
              initialValue:
                  devices.any((device) => device.id == selectedId) ? selectedId : null,
              items: <DropdownMenuItem<String?>>[
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('System default'),
                ),
                ...devices.map(
                  (DeviceOption device) => DropdownMenuItem<String?>(
                    value: device.id,
                    child: Text(device.label),
                  ),
                ),
              ],
              onChanged: onSelectDevice,
            ),
            const SizedBox(height: 20),
            PeakMeter(
              label: meterLeftLabel,
              value: leftPeak,
              color: accentColor,
            ),
            const SizedBox(height: 12),
            PeakMeter(
              label: meterRightLabel,
              value: rightPeak,
              color: secondaryColor,
            ),
          ],
        ),
      ),
    );
  }
}
