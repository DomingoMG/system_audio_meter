import 'dart:async';

import 'package:flutter/material.dart';
import 'package:system_audio_meter/system_audio_meter.dart';

void main() {
  runApp(const MeterExampleApp());
}

class MeterExampleApp extends StatelessWidget {
  const MeterExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'System Audio Meter',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const MeterHomePage(),
    );
  }
}

class MeterHomePage extends StatefulWidget {
  const MeterHomePage({super.key});

  @override
  State<MeterHomePage> createState() => _MeterHomePageState();
}

class _MeterHomePageState extends State<MeterHomePage> {
  static const double _silenceThreshold = 0.05;
  static const Duration _silenceDuration = Duration(seconds: 5);
  static const List<AudioSilenceStage> _silenceStages = <AudioSilenceStage>[
    AudioSilenceStage(
      id: 'warning',
      after: Duration(seconds: 5),
      severity: 'warning',
      label: 'Warning',
    ),
    AudioSilenceStage(
      id: 'critical',
      after: Duration(seconds: 10),
      severity: 'critical',
      label: 'Critical',
    ),
  ];

  final SystemAudioMeter _meter = SystemAudioMeter.instance;
  late final AudioSilenceTracker _silenceTracker;

  StreamSubscription<AudioLevels>? _outputSubscription;
  StreamSubscription<AudioLevels>? _inputSubscription;
  StreamSubscription<AudioDeviceEvent>? _deviceEventSubscription;
  StreamSubscription<AudioSilenceState>? _silenceSubscription;
  List<AudioOutputDevice> _outputDevices = const <AudioOutputDevice>[];
  List<AudioInputDevice> _inputDevices = const <AudioInputDevice>[];
  AudioOutputDevice? _currentOutputDevice;
  AudioInputDevice? _currentInputDevice;
  double _outputLeftPeak = 0.0;
  double _outputRightPeak = 0.0;
  double _inputLeftPeak = 0.0;
  double _inputRightPeak = 0.0;
  bool _isOutputRunning = false;
  bool _isInputRunning = false;
  bool _silenceDetectionEnabled = false;
  bool _isOutputSilent = false;
  bool _isInputSilent = false;
  AudioSilenceStage? _outputSilenceStage;
  AudioSilenceStage? _inputSilenceStage;
  bool _shouldResumeOutput = false;
  bool _shouldResumeInput = false;
  String? _outputStatusMessage;
  String? _inputStatusMessage;
  String? _outputSilenceStatusMessage;
  String? _inputSilenceStatusMessage;
  String? _errorMessage;
  bool _refreshingDevices = false;

  @override
  void initState() {
    super.initState();
    _silenceTracker = _meter.createSilenceTracker(stages: _silenceStages);
    _initialize();
  }

  @override
  void dispose() {
    _outputSubscription?.cancel();
    _inputSubscription?.cancel();
    _deviceEventSubscription?.cancel();
    _silenceSubscription?.cancel();
    _silenceTracker.dispose();
    unawaited(_meter.disableSilenceDetection(flow: AudioDeviceFlow.output));
    unawaited(_meter.disableSilenceDetection(flow: AudioDeviceFlow.input));
    super.dispose();
  }

  Future<void> _initialize() async {
    _listenToSilenceEvents();
    await _configureSilenceDetection();
    _listenToDeviceEvents();
    await _refreshDevices();
    await _refreshRunningState();
  }

  Future<void> _configureSilenceDetection() async {
    try {
      await _meter.enableSilenceDetection(
        flow: AudioDeviceFlow.output,
        threshold: _silenceThreshold,
        duration: _silenceDuration,
      );
      await _meter.enableSilenceDetection(
        flow: AudioDeviceFlow.input,
        threshold: _silenceThreshold,
        duration: _silenceDuration,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _silenceDetectionEnabled = true;
        final message =
            'Silence detection enabled at ${(_silenceThreshold * 100).toStringAsFixed(0)}% for ${_silenceDuration.inSeconds}s. Stages: 5s warning, 10s critical.';
        _outputSilenceStatusMessage = message;
        _inputSilenceStatusMessage = message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '$error';
        _silenceDetectionEnabled = false;
      });
    }
  }

  void _listenToSilenceEvents() {
    _silenceSubscription ??= _silenceTracker.states.listen((AudioSilenceState state) {
      if (!mounted) {
        return;
      }

      setState(() {
        final flowLabel = state.flow == AudioDeviceFlow.input ? 'Input' : 'Output';
        final deviceSuffix = state.deviceName == null || state.deviceName!.isEmpty
            ? ''
            : ' on ${state.deviceName}';
        final stageLabel = state.currentStage?.label ?? state.currentStage?.id;
        final stageSuffix =
            stageLabel == null ? '' : ' Stage: $stageLabel.';
        final message = switch (state.type) {
          AudioSilenceStateType.silent =>
            '$flowLabel silence started at ${(state.peakLevel * 100).toStringAsFixed(1)}% peak$deviceSuffix.',
          AudioSilenceStateType.stageChanged =>
            '$flowLabel silence has lasted ${state.silentFor.inSeconds}s.$stageSuffix$deviceSuffix',
          AudioSilenceStateType.active =>
            '$flowLabel silence ended after ${state.silentFor.inSeconds}s at ${(state.peakLevel * 100).toStringAsFixed(1)}% peak$deviceSuffix.',
        };

        if (state.flow == AudioDeviceFlow.input) {
          _isInputSilent = state.isSilent;
          _inputSilenceStage = state.currentStage;
          _inputSilenceStatusMessage = message;
        } else {
          _isOutputSilent = state.isSilent;
          _outputSilenceStage = state.currentStage;
          _outputSilenceStatusMessage = message;
        }
      });
    });
  }

  void _listenToDeviceEvents() {
    _deviceEventSubscription ??= _meter.deviceEvents.listen((AudioDeviceEvent event) {
      if (!mounted) {
        return;
      }

      if (event.flow == AudioDeviceFlow.input) {
        if (event.kind == AudioDeviceEventKind.disconnected) {
          _silenceTracker.reset(
            flow: AudioDeviceFlow.input,
            emitState: false,
          );
          setState(() {
            _inputLeftPeak = 0.0;
            _inputRightPeak = 0.0;
            _isInputSilent = false;
            _inputSilenceStage = null;
            _currentInputDevice = null;
            _isInputRunning = false;
            _inputStatusMessage = 'Input device disconnected or unavailable.';
          });
          _refreshDevicesSoon();
          return;
        }

        setState(() {
          _errorMessage = null;
          _inputStatusMessage = event.deviceName == null || event.deviceName!.isEmpty
              ? 'Input device reconnected.'
              : 'Input device reconnected: ${event.deviceName}';
        });
        _refreshDevicesSoon();
        if (_shouldResumeInput) {
          unawaited(_meter.startInput());
          unawaited(_refreshRunningState());
        }
        return;
      }

      if (event.kind == AudioDeviceEventKind.disconnected) {
        _silenceTracker.reset(
          flow: AudioDeviceFlow.output,
          emitState: false,
        );
        setState(() {
          _outputLeftPeak = 0.0;
          _outputRightPeak = 0.0;
          _isOutputSilent = false;
          _outputSilenceStage = null;
          _currentOutputDevice = null;
          _isOutputRunning = false;
          _outputStatusMessage = 'Output device disconnected or unavailable.';
        });
        _refreshDevicesSoon();
        return;
      }

      setState(() {
        _errorMessage = null;
        _outputStatusMessage = event.deviceName == null || event.deviceName!.isEmpty
            ? 'Output device reconnected.'
            : 'Output device reconnected: ${event.deviceName}';
      });
      _refreshDevicesSoon();
      if (_shouldResumeOutput) {
        unawaited(_meter.start());
        unawaited(_refreshRunningState());
      }
    });
  }

  Future<void> _refreshRunningState() async {
    final isOutputRunning = await _meter.isRunning;
    final isInputRunning = await _meter.isInputRunning;
    if (!mounted) {
      return;
    }
    setState(() {
      _isOutputRunning = isOutputRunning;
      _isInputRunning = isInputRunning;
    });
  }

  Future<void> _refreshDevices() async {
    if (_refreshingDevices) {
      return;
    }
    _refreshingDevices = true;
    try {
      final outputDevices = await _meter.getOutputDevices();
      final inputDevices = await _meter.getInputDevices();
      final currentOutput = await _meter.getCurrentOutputDevice();
      final currentInput = await _meter.getCurrentInputDevice();
      if (!mounted) {
        return;
      }
      setState(() {
        _outputDevices = outputDevices;
        _inputDevices = inputDevices;
        _currentOutputDevice = currentOutput;
        _currentInputDevice = currentInput;
        _outputStatusMessage = outputDevices.isEmpty
            ? 'No output devices reported by this platform yet.'
            : _outputStatusMessage;
        _inputStatusMessage = inputDevices.isEmpty
            ? 'No input devices reported by this platform yet.'
            : _inputStatusMessage;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '$error';
      });
    } finally {
      _refreshingDevices = false;
    }
  }

  void _refreshDevicesSoon() {
    unawaited(_refreshDevices());
  }

  Future<void> _startOutputMeter() async {
    setState(() {
      _errorMessage = null;
      _outputStatusMessage = 'Starting output meter...';
      _shouldResumeOutput = true;
    });

    _outputSubscription ??= _meter.outputLevels.listen(
      (AudioLevels levels) {
        if (!mounted) {
          return;
        }
        final previousDeviceId = _currentOutputDevice?.id;
        setState(() {
          _outputLeftPeak = levels.leftPeak;
          _outputRightPeak = levels.rightPeak;
          _isOutputRunning = true;
          _currentOutputDevice = AudioOutputDevice(
            id: levels.outputDeviceId ?? _currentOutputDevice?.id ?? '',
            name: levels.outputDeviceName ??
                _currentOutputDevice?.name ??
                'Default output',
            isDefault: _currentOutputDevice?.isDefault ?? true,
          );
          _errorMessage = null;
          _outputStatusMessage =
              'Streaming from ${levels.outputDeviceName ?? 'default output'}';
        });
        if (levels.outputDeviceId != null &&
            levels.outputDeviceId != previousDeviceId) {
          _refreshDevicesSoon();
        }
      },
      onError: (Object error) {
        if (!mounted) {
          return;
        }
        _silenceTracker.reset(
          flow: AudioDeviceFlow.output,
          emitState: false,
        );
        setState(() {
          _outputLeftPeak = 0.0;
          _outputRightPeak = 0.0;
          _isOutputSilent = false;
          _outputSilenceStage = null;
          _currentOutputDevice = null;
          _errorMessage = '$error';
          _isOutputRunning = false;
          _outputStatusMessage = 'Output device disconnected or unavailable.';
        });
        _refreshDevicesSoon();
      },
    );

    try {
      await _meter.start();
      await _refreshRunningState();
      if (!mounted) {
        return;
      }
      setState(() {
        _outputStatusMessage = 'Output meter started.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '$error';
        _outputStatusMessage = null;
      });
    }
  }

  Future<void> _stopOutputMeter() async {
    try {
      await _meter.stop();
      _silenceTracker.reset(
        flow: AudioDeviceFlow.output,
        emitState: false,
      );
      await _refreshRunningState();
      if (!mounted) {
        return;
      }
      setState(() {
        _outputLeftPeak = 0.0;
        _outputRightPeak = 0.0;
        _isOutputSilent = false;
        _outputSilenceStage = null;
        _outputStatusMessage = 'Output meter stopped.';
        _shouldResumeOutput = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '$error';
      });
    }
  }

  Future<void> _selectOutputDevice(String? deviceId) async {
    try {
      await _meter.setOutputDevice(deviceId);
      await _refreshDevices();
      if (_isOutputRunning) {
        await _meter.start();
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _outputStatusMessage = deviceId == null
            ? 'Monitoring the default output device.'
            : 'Output device updated.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '$error';
      });
    }
  }

  Future<void> _startInputMeter() async {
    setState(() {
      _errorMessage = null;
      _inputStatusMessage = 'Starting input meter...';
      _shouldResumeInput = true;
    });

    _inputSubscription ??= _meter.inputLevels.listen(
      (AudioLevels levels) {
        if (!mounted) {
          return;
        }
        final previousDeviceId = _currentInputDevice?.id;
        setState(() {
          _inputLeftPeak = levels.leftPeak;
          _inputRightPeak = levels.rightPeak;
          _isInputRunning = true;
          _currentInputDevice = AudioInputDevice(
            id: levels.inputDeviceId ?? _currentInputDevice?.id ?? '',
            name:
                levels.inputDeviceName ?? _currentInputDevice?.name ?? 'Default input',
            isDefault: _currentInputDevice?.isDefault ?? true,
          );
          _errorMessage = null;
          _inputStatusMessage =
              'Streaming from ${levels.inputDeviceName ?? 'default input'}';
        });
        if (levels.inputDeviceId != null &&
            levels.inputDeviceId != previousDeviceId) {
          _refreshDevicesSoon();
        }
      },
      onError: (Object error) {
        if (!mounted) {
          return;
        }
        _silenceTracker.reset(
          flow: AudioDeviceFlow.input,
          emitState: false,
        );
        setState(() {
          _inputLeftPeak = 0.0;
          _inputRightPeak = 0.0;
          _isInputSilent = false;
          _inputSilenceStage = null;
          _currentInputDevice = null;
          _errorMessage = '$error';
          _isInputRunning = false;
          _inputStatusMessage = 'Input device disconnected or unavailable.';
        });
        _refreshDevicesSoon();
      },
    );

    try {
      await _meter.startInput();
      await _refreshRunningState();
      if (!mounted) {
        return;
      }
      setState(() {
        _inputStatusMessage = 'Input meter started.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '$error';
        _inputStatusMessage = null;
      });
    }
  }

  Future<void> _stopInputMeter() async {
    try {
      await _meter.stopInput();
      _silenceTracker.reset(
        flow: AudioDeviceFlow.input,
        emitState: false,
      );
      await _refreshRunningState();
      if (!mounted) {
        return;
      }
      setState(() {
        _inputLeftPeak = 0.0;
        _inputRightPeak = 0.0;
        _isInputSilent = false;
        _inputSilenceStage = null;
        _inputStatusMessage = 'Input meter stopped.';
        _shouldResumeInput = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '$error';
      });
    }
  }

  Future<void> _selectInputDevice(String? deviceId) async {
    try {
      await _meter.setInputDevice(deviceId);
      await _refreshDevices();
      if (_isInputRunning) {
        await _meter.startInput();
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _inputStatusMessage = deviceId == null
            ? 'Monitoring the default input device.'
            : 'Input device updated.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('System Audio Meter'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          _ErrorCard(errorMessage: _errorMessage),
          _MeterSection(
            title: 'Output device',
            isRunning: _isOutputRunning,
            statusMessage: _outputStatusMessage,
            selectedId: _currentOutputDevice?.id,
            devices: _outputDevices
                .map(
                  (AudioOutputDevice device) => _DeviceOption(
                    id: device.id,
                    label:
                        device.isDefault ? '${device.name} (default)' : device.name,
                  ),
                )
                .toList(growable: false),
            meterLeftLabel: 'Left',
            meterRightLabel: 'Right',
            leftPeak: _outputLeftPeak,
            rightPeak: _outputRightPeak,
            accentColor: const Color(0xFF0F766E),
            secondaryColor: const Color(0xFFEA580C),
            supplemental: _SilenceStatusCard(
              enabled: _silenceDetectionEnabled,
              isSilent: _isOutputSilent,
              title: 'Output silence detector',
              stage: _outputSilenceStage,
              threshold: _silenceThreshold,
              duration: _silenceDuration,
              statusMessage: _outputSilenceStatusMessage,
            ),
            onStart: _startOutputMeter,
            onStop: _stopOutputMeter,
            onRefresh: _refreshDevices,
            onSelectDevice: _selectOutputDevice,
          ),
          const SizedBox(height: 20),
          _MeterSection(
            title: 'Input device',
            isRunning: _isInputRunning,
            statusMessage: _inputStatusMessage,
            selectedId: _currentInputDevice?.id,
            devices: _inputDevices
                .map(
                  (AudioInputDevice device) => _DeviceOption(
                    id: device.id,
                    label:
                        device.isDefault ? '${device.name} (default)' : device.name,
                  ),
                )
                .toList(growable: false),
            meterLeftLabel: 'Channel 1',
            meterRightLabel: 'Channel 2',
            leftPeak: _inputLeftPeak,
            rightPeak: _inputRightPeak,
            accentColor: const Color(0xFF2563EB),
            secondaryColor: const Color(0xFFD97706),
            supplemental: _SilenceStatusCard(
              enabled: _silenceDetectionEnabled,
              isSilent: _isInputSilent,
              title: 'Input silence detector',
              stage: _inputSilenceStage,
              threshold: _silenceThreshold,
              duration: _silenceDuration,
              statusMessage: _inputSilenceStatusMessage,
            ),
            onStart: _startInputMeter,
            onStop: _stopInputMeter,
            onRefresh: _refreshDevices,
            onSelectDevice: _selectInputDevice,
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.errorMessage});

  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    if (errorMessage == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            errorMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ),
    );
  }
}

class _MeterSection extends StatelessWidget {
  const _MeterSection({
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
  final List<_DeviceOption> devices;
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
                  (_DeviceOption device) => DropdownMenuItem<String?>(
                    value: device.id,
                    child: Text(device.label),
                  ),
                ),
              ],
              onChanged: onSelectDevice,
            ),
            const SizedBox(height: 20),
            _PeakMeter(
              label: meterLeftLabel,
              value: leftPeak,
              color: accentColor,
            ),
            const SizedBox(height: 12),
            _PeakMeter(
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

class _DeviceOption {
  const _DeviceOption({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;
}

class _PeakMeter extends StatelessWidget {
  const _PeakMeter({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final safeValue = value.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(label)),
            Text('${(safeValue * 100).toStringAsFixed(0)}%'),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 18,
            value: safeValue,
            color: color,
            backgroundColor: color.withValues(alpha: 0.15),
          ),
        ),
      ],
    );
  }
}

class _SilenceStatusCard extends StatelessWidget {
  const _SilenceStatusCard({
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
