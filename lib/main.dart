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
    return MaterialApp(
      home: Scaffold(body: GameWidget(game: BlackHoleGame())),
    );
  }
}
