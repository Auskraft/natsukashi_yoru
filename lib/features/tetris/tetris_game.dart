import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../core/components/game_scaffold.dart';

/// Точка входа фичи «Tetris».
class TetrisGame extends FlameGame {
  // TODO(iteration-2): стакан, тетрамино, гравитация, поворот, сжигание линий.
}

class TetrisScreen extends StatelessWidget {
  const TetrisScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const GameScaffold(
      title: 'Tetris',
      body: ComingSoonBody(icon: Icons.view_module, color: Color(0xFF7C5CFF)),
    );
  }
}
