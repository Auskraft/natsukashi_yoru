import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../../core/components/overlay_kit.dart';
import '../game/game2048_flame_game.dart';

/// HUD «2048»: счёт и рекорд сверху, максимальная плитка и кнопка паузы справа,
/// внизу — подсказка по управлению (+ FPS в debug-сборке).
class Game2048Hud extends StatelessWidget {
  const Game2048Hud({super.key, required this.game, required this.best});

  final Game2048FlameGame game;
  final int best;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ValueListenableBuilder<int>(
                  valueListenable: game.score,
                  builder: (_, score, _) =>
                      StatBlock(label: 'СЧЁТ', value: '$score'),
                ),
                ValueListenableBuilder<int>(
                  valueListenable: game.maxTile,
                  builder: (_, maxTile, _) => StatBlock(
                    label: 'МАКС',
                    value: '$maxTile',
                    color: const Color(0xFF4ECDC4),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatBlock(
                      label: 'РЕКОРД',
                      value: '$best',
                      color: const Color(0xFFFFD54F),
                      alignEnd: true,
                    ),
                    const SizedBox(width: 10),
                    PauseButton(onTap: game.togglePause),
                  ],
                ),
              ],
            ),
            const Spacer(),
            _BottomReadout(game: game),
          ],
        ),
      ),
    );
  }
}

/// Нижняя строка: подсказка по свайпам (+ FPS в debug-сборке).
class _BottomReadout extends StatelessWidget {
  const _BottomReadout({required this.game});

  final Game2048FlameGame game;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: Colors.white.withValues(alpha: 0.35),
      fontSize: 12,
      letterSpacing: 1.2,
      fontWeight: FontWeight.w700,
    );
    final hint = Text(
      'СВАЙП — двигай плитки · одинаковые сливаются',
      style: style,
      textAlign: TextAlign.center,
    );
    if (!kDebugMode) return hint;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        hint,
        const SizedBox(height: 2),
        ValueListenableBuilder<double>(
          valueListenable: game.fps,
          builder: (_, fps, _) => Text('${fps.round()} FPS', style: style),
        ),
      ],
    );
  }
}
