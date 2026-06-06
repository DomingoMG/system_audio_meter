import 'dart:async';

import 'package:flutter/material.dart';
import 'package:system_audio_meter/system_audio_meter.dart';
import 'package:system_audio_meter_example/widgets/error_card.dart';
import 'package:system_audio_meter_example/widgets/meter_section.dart';
import 'package:system_audio_meter_example/widgets/silence_status_card.dart';

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
          ErrorCard(errorMessage: _errorMessage),
          MeterSection(
            title: 'Output device',
            isRunning: _isOutputRunning,
            statusMessage: _outputStatusMessage,
            selectedId: _currentOutputDevice?.id,
            devices: _outputDevices
                .map(
                  (AudioOutputDevice device) => DeviceOption(
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
            supplemental: SilenceStatusCard(
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
          MeterSection(
            title: 'Input device',
            isRunning: _isInputRunning,
            statusMessage: _inputStatusMessage,
            selectedId: _currentInputDevice?.id,
            devices: _inputDevices
                .map(
                  (AudioInputDevice device) => DeviceOption(
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
            supplemental: SilenceStatusCard(
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
