import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../core/components/game_scaffold.dart';

/// Точка входа фичи «Match3».
class Match3Game extends FlameGame {
  // TODO(iteration-2): сетка, поиск рядов 3+, схлопывание, гравитация фишек.
}

class Match3Screen extends StatelessWidget {
  const Match3Screen({super.key});

  @override
  Widget build(BuildContext context) {
    return const GameScaffold(
      title: 'Match3',
      body: ComingSoonBody(icon: Icons.grid_view, color: Color(0xFFFF6FAE)),
    );
  }
}
