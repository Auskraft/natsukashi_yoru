import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../core/components/game_scaffold.dart';

/// Точка входа фичи «Minesweeper».
class MinesweeperGame extends FlameGame {
  // TODO(iteration-2): поле, мины, числа-подсказки, флаги, авто-раскрытие.
}

class MinesweeperScreen extends StatelessWidget {
  const MinesweeperScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const GameScaffold(
      title: 'Minesweeper',
      body: ComingSoonBody(icon: Icons.flag, color: Color(0xFF7C5CFF)),
    );
  }
}
