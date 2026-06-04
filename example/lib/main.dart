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
  final SystemAudioMeter _meter = SystemAudioMeter.instance;

  StreamSubscription<AudioLevels>? _subscription;
  List<AudioOutputDevice> _devices = const <AudioOutputDevice>[];
  AudioOutputDevice? _currentDevice;
  double _leftPeak = 0.0;
  double _rightPeak = 0.0;
  bool _isRunning = false;
  String? _statusMessage;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _refreshDevices();
    await _refreshRunningState();
  }

  Future<void> _refreshRunningState() async {
    final isRunning = await _meter.isRunning;
    if (!mounted) {
      return;
    }
    setState(() {
      _isRunning = isRunning;
    });
  }

  Future<void> _refreshDevices() async {
    try {
      final devices = await _meter.getOutputDevices();
      final current = await _meter.getCurrentOutputDevice();
      if (!mounted) {
        return;
      }
      setState(() {
        _devices = devices;
        _currentDevice = current;
        _statusMessage = devices.isEmpty
            ? 'No output devices reported by this platform yet.'
            : null;
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

  Future<void> _startMeter() async {
    setState(() {
      _errorMessage = null;
      _statusMessage = 'Starting meter...';
    });

    _subscription ??= _meter.levels.listen(
      (AudioLevels levels) {
        if (!mounted) {
          return;
        }
        setState(() {
          _leftPeak = levels.leftPeak;
          _rightPeak = levels.rightPeak;
          _currentDevice = AudioOutputDevice(
            id: levels.outputDeviceId ?? _currentDevice?.id ?? '',
            name: levels.outputDeviceName ??
                _currentDevice?.name ??
                'Default output',
            isDefault: _currentDevice?.isDefault ?? true,
          );
          _statusMessage =
              'Streaming from ${levels.outputDeviceName ?? 'default output'}';
        });
      },
      onError: (Object error) {
        if (!mounted) {
          return;
        }
        setState(() {
          _errorMessage = '$error';
          _isRunning = false;
        });
      },
    );

    try {
      await _meter.start();
      await _refreshRunningState();
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = 'Meter started.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '$error';
        _statusMessage = null;
      });
    }
  }

  Future<void> _stopMeter() async {
    try {
      await _meter.stop();
      await _refreshRunningState();
      if (!mounted) {
        return;
      }
      setState(() {
        _leftPeak = 0.0;
        _rightPeak = 0.0;
        _statusMessage = 'Meter stopped.';
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

  Future<void> _selectDevice(String? deviceId) async {
    try {
      await _meter.setOutputDevice(deviceId);
      await _refreshDevices();
      if (_isRunning) {
        await _meter.start();
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = deviceId == null
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

  @override
  Widget build(BuildContext context) {
    final selectedId = _currentDevice?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('System Audio Meter'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          _StatusCard(
            isRunning: _isRunning,
            statusMessage: _statusMessage,
            errorMessage: _errorMessage,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              FilledButton.icon(
                onPressed: _startMeter,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start meter'),
              ),
              OutlinedButton.icon(
                onPressed: _stopMeter,
                icon: const Icon(Icons.stop),
                label: const Text('Stop meter'),
              ),
              TextButton.icon(
                onPressed: _refreshDevices,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh devices'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Output device',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _devices.any((device) => device.id == selectedId)
                ? selectedId
                : null,
            items: <DropdownMenuItem<String?>>[
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('System default'),
              ),
              ..._devices.map(
                (AudioOutputDevice device) => DropdownMenuItem<String?>(
                  value: device.id,
                  child: Text(
                    device.isDefault ? '${device.name} (default)' : device.name,
                  ),
                ),
              ),
            ],
            onChanged: _selectDevice,
          ),
          const SizedBox(height: 24),
          Text(
            'Stereo peak meter',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          _PeakMeter(
              label: 'Left', value: _leftPeak, color: const Color(0xFF0F766E)),
          const SizedBox(height: 12),
          _PeakMeter(
              label: 'Right',
              value: _rightPeak,
              color: const Color(0xFFEA580C)),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.isRunning,
    required this.statusMessage,
    required this.errorMessage,
  });

  final bool isRunning;
  final String? statusMessage;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              isRunning ? 'Running' : 'Idle',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (statusMessage != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(statusMessage!),
            ],
            if (errorMessage != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                errorMessage!,
                style: TextStyle(color: colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
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
