import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../../core/components/overlay_kit.dart';
import '../game/breakout_flame_game.dart';

/// HUD: сверху счёт/рекорд + кнопка паузы справа, посередине бейдж комбо,
/// снизу — жизни/уровень и FPS (только в debug-сборке).
class BreakoutHud extends StatelessWidget {
  const BreakoutHud({super.key, required this.game, required this.best});

  final BreakoutFlameGame game;
  final int best;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  valueListenable: game.combo,
                  builder: (_, combo, _) => ComboBadge(combo: combo),
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

/// Нижняя строка: жизни, уровень и FPS (в debug). Заполняет низ под полем.
class _BottomReadout extends StatelessWidget {
  const _BottomReadout({required this.game});

  final BreakoutFlameGame game;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: Colors.white.withValues(alpha: 0.4),
      fontSize: 12,
      letterSpacing: 1.5,
      fontWeight: FontWeight.w700,
    );
    return AnimatedBuilder(
      animation: Listenable.merge([game.lives, game.level, game.fps]),
      builder: (_, _) {
        final hearts = '❤' * game.lives.value;
        final parts = <String>[
          'ЖИЗНИ ${hearts.isEmpty ? '—' : hearts}',
          'УРОВЕНЬ ${game.level.value}',
          if (kDebugMode) '${game.fps.value.round()} FPS',
        ];
        return Text(
          parts.join('     ·     '),
          style: style,
          textAlign: TextAlign.center,
        );
      },
    );
  }
}
