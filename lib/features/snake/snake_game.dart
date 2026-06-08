import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../core/components/game_scaffold.dart';

/// Точка входа фичи «Snake».
///
/// Архитектурный задел: [SnakeGame] — будущая Flame-игра (GameLoop, ввод,
/// рендер). Пока пустая. [SnakeScreen] — экран-хост, сейчас показывает
/// заглушку, позже здесь будет `GameWidget(game: SnakeGame())` с HUD-оверлеями.
class SnakeGame extends FlameGame {
  // TODO(iteration-2): сетка, змейка, еда, обработка свайпов, столкновения.
}

class SnakeScreen extends StatelessWidget {
  const SnakeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const GameScaffold(
      title: 'Snake',
      body: ComingSoonBody(icon: Icons.gesture, color: Color(0xFF4ECDC4)),
    );
  }
}
