import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:flame/game.dart';
import 'game/blackhole_game.dart';
import 'game/blackhole_game_3d.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: HomeScreen());
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Black Hole Sim')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const _GameScreen2D()));
            },
            child: const Text('Run 2D'),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const _GameScreen3D()));
            },
            child: const Text('Run 3D (raytraced)'),
          ),
        ],
      ),
    );
  }
}

class _GameScreen2D extends StatelessWidget {
  const _GameScreen2D();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('2D Sim')),
      body: GameWidget(game: BlackHoleSim2d()),
    );
  }
}

class _GameScreen3D extends StatefulWidget {
  const _GameScreen3D();
  @override
  State<_GameScreen3D> createState() => _GameScreen3DState();
}

class _GameScreen3DState extends State<_GameScreen3D> {
  double spin = 0.0; // a/M in [0,1]
  double inclDeg = 0.0; // degrees

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('3D Sim')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Spin a/M: ${spin.toStringAsFixed(2)}'),
                Slider(
                  value: spin,
                  onChanged: (v) => setState(() => spin = v),
                  min: 0.0,
                  max: 1.0,
                ),
                Text('Inclination: ${inclDeg.toStringAsFixed(0)}°'),
                Slider(
                  value: inclDeg,
                  onChanged: (v) => setState(() => inclDeg = v),
                  min: 0.0,
                  max: 90.0,
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Render at a modest internal resolution for speed, then scale up
                const baseW = 320; // adjust for quality/perf
                final aspect = constraints.maxWidth / constraints.maxHeight;
                final w = baseW;
                final h = (baseW / aspect).round().clamp(64, 720);
                final game = BlackHoleSim3d(
                  imageWidth: w,
                  imageHeight: h,
                  cubeHalfSize: 2.5e11,
                  spinFraction: spin,
                  inclinationRad: inclDeg * math.pi / 180.0,
                );
                return GameWidget(game: game);
              },
            ),
          ),
        ],
      ),
    );
  }
}
