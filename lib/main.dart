import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:flame/game.dart';
import 'game/blackhole_game.dart';
import 'game/blackhole_game_3d.dart';
import 'game/native_texture.dart';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:ui' as ui show instantiateImageCodec, ImageByteFormat;

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
                  min: -90.0,
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
                if (Platform.isMacOS) {
                  return _MacOSTextureView(
                    width: w,
                    height: h,
                    inclDeg: inclDeg,
                  );
                }
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

class _MacOSTextureView extends StatefulWidget {
  final int width;
  final int height;
  final double inclDeg;
  const _MacOSTextureView({required this.width, required this.height, required this.inclDeg});
  @override
  State<_MacOSTextureView> createState() => _MacOSTextureViewState();
}

class _MacOSTextureViewState extends State<_MacOSTextureView> {
  int? _textureId;
  Uint8List? _bgRgba;
  int _bgW = 0;
  int _bgH = 0;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    if (_textureId == null) {
      final id = await NativeTexture.create(widget.width, widget.height);
      if (mounted) {
        setState(() => _textureId = id);
      }
    }
    // Load background once
    if (_bgRgba == null) {
      final bd = await DefaultAssetBundle.of(context).load('assets/space.png');
      // Decode to RGBA using ui.decodeImageFromList
  final codec = await ui.instantiateImageCodec(bd.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      final img = frame.image;
  final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData != null) {
        _bgRgba = byteData.buffer.asUint8List();
        _bgW = img.width; _bgH = img.height;
        await NativeTexture.setBackground(rgba: _bgRgba!, width: _bgW, height: _bgH);
      }
    }
    await _render();
  }

  Future<void> _render() async {
    // Basic camera matching the game defaults
    final R = 2.0e11;
    final ci = math.cos(widget.inclDeg * math.pi / 180.0);
    final si = math.sin(widget.inclDeg * math.pi / 180.0);
    final pos = [-R * ci, 0.0, R * si];
    final target = [0.0, 0.0, 0.0];
    final up = [si, 0.0, ci];
    await NativeTexture.render(
      pos: pos,
      target: target,
      up: up,
      fovY: math.pi / 2,
      rS: 2.0 * 6.67430e-11 * 8.54e36 / (299792458.0 * 299792458.0),
      cubeHalfSize: 2.5e11,
      maxSteps: 4000,
      dLambda: 1.0,
      width: widget.width,
      height: widget.height,
    );
  }

  @override
  void didUpdateWidget(covariant _MacOSTextureView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.width != widget.width || oldWidget.height != widget.height || oldWidget.inclDeg != widget.inclDeg) {
      _setup();
    }
  }

  @override
  void dispose() {
    NativeTexture.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = _textureId;
    if (id == null) return const Center(child: CircularProgressIndicator());
    return Texture(textureId: id);
  }
}
