import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'game/blackhole_game.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    final game = BlackHoleGame();
    return MaterialApp(
      home: Scaffold(
        body: GameWidget(
          game: game,
          overlayBuilderMap: {
            BlackHoleGame.overlayHud: (ctx, g) {
              final bh = g as BlackHoleGame;
              return Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ValueListenableBuilder<int>(
                            valueListenable: bh.rayCount,
                            builder: (context, count, _) => Text(
                              'Rays: $count',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'GPU',
                                style: TextStyle(color: Colors.white),
                              ),
                              const SizedBox(width: 6),
                              ValueListenableBuilder<bool>(
                                valueListenable: bh.gpuOn,
                                builder: (context, gpu, _) => Switch(
                                  value: gpu && bh.metal.isAvailable,
                                  onChanged: bh.metal.isAvailable
                                      ? (v) {
                                          bh.useGpu = v;
                                          bh.gpuOn.value = v;
                                        }
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          },
        ),
      ),
    );
  }
}
