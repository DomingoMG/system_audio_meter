import 'package:flutter/material.dart';
import 'package:system_audio_meter_example/pages/meter_page.dart';

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