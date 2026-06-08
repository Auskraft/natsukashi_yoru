import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../core/components/game_scaffold.dart';

/// Точка входа фичи «Puyo Puyo».
class PuyoPuyoGame extends FlameGame {
  // TODO(iteration-2): падающие пары шариков, группы 4+, combo-цепочки.
}

class PuyoPuyoScreen extends StatelessWidget {
  const PuyoPuyoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const GameScaffold(
      title: 'Puyo Puyo',
      body: ComingSoonBody(icon: Icons.bubble_chart, color: Color(0xFFFF6FAE)),
    );
  }
}
