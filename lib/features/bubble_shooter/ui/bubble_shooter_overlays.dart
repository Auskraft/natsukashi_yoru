import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../../core/components/overlay_kit.dart';
import '../game/bubble_shooter_flame_game.dart';

/// HUD «Bubble Shooter»: сверху счёт и рекорд (справа — кнопка паузы), по центру
/// бейдж комбо за крупные сносы, снизу — счётчик пузырей и FPS в debug-сборке.
class BubbleShooterHud extends StatelessWidget {
  const BubbleShooterHud({super.key, required this.game, required this.best});

  final BubbleShooterFlameGame game;
  final int best;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ValueListenableBuilder<int>(
                  valueListenable: game.score,
                  builder: (_, score, _) =>
                      StatBlock(label: 'СЧЁТ', value: '$score'),
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
            const SizedBox(height: 8),
            Center(
              child: ValueListenableBuilder<int>(
                valueListenable: game.combo,
                builder: (_, combo, _) => ComboBadge(combo: combo, label: 'POP'),
              ),
            ),
            const Spacer(),
            _BottomReadout(game: game),
          ],
        ),
      ),
    );
  }
}

/// Нижняя строка статистики: число пузырей на поле и FPS (только в debug).
class _BottomReadout extends StatelessWidget {
  const _BottomReadout({required this.game});

  final BubbleShooterFlameGame game;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: Colors.white.withValues(alpha: 0.35),
      fontSize: 12,
      letterSpacing: 1.5,
      fontWeight: FontWeight.w700,
    );
    return AnimatedBuilder(
      animation: Listenable.merge([game.level, game.bubbles, game.fps]),
      builder: (_, _) {
        final parts = <String>[
          'УРОВЕНЬ ${game.level.value}',
          'ПУЗЫРЕЙ ${game.bubbles.value}',
          if (kDebugMode) '${game.fps.value.round()} FPS',
        ];
        return Text(parts.join('     ·     '), style: style);
      },
    );
  }
}
