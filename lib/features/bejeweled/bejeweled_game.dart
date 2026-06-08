import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../core/components/game_scaffold.dart';

/// Точка входа фичи «Bejeweled».
class BejeweledGame extends FlameGame {
  // TODO(iteration-2): обмен соседних камней, проверка матча, каскады.
}

class BejeweledScreen extends StatelessWidget {
  const BejeweledScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const GameScaffold(
      title: 'Bejeweled',
      body: ComingSoonBody(icon: Icons.diamond, color: Color(0xFF4ECDC4)),
    );
  }
}
