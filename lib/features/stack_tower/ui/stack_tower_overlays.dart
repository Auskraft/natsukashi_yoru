import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../../core/components/overlay_kit.dart';
import '../game/stack_tower_flame_game.dart';

/// HUD «Stack»: сверху счёт (высота башни) и рекорд + кнопка паузы справа,
/// по центру — бейдж серии идеальных установок; FPS только в debug-сборке.
class StackTowerHud extends StatelessWidget {
  const StackTowerHud({super.key, required this.game, required this.best});

  final StackFlameGame game;
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
                      StatBlock(label: 'БАШНЯ', value: '$score'),
                ),
                ValueListenableBuilder<int>(
                  valueListenable: game.combo,
                  builder: (_, combo, _) =>
                      ComboBadge(combo: combo, label: 'ИДЕАЛ'),
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

/// Нижняя строка: скорость движения и FPS (в debug). Заполняет низ экрана.
class _BottomReadout extends StatelessWidget {
  const _BottomReadout({required this.game});

  final StackFlameGame game;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: Colors.white.withValues(alpha: 0.35),
      fontSize: 12,
      letterSpacing: 1.5,
      fontWeight: FontWeight.w700,
    );
    return AnimatedBuilder(
      animation: Listenable.merge([game.speed, game.fps]),
      builder: (_, _) {
        final parts = <String>[
          'СКОРОСТЬ ×${game.speed.value.toStringAsFixed(1)}',
          if (kDebugMode) '${game.fps.value.round()} FPS',
        ];
        return Text(parts.join('     ·     '), style: style);
      },
    );
  }
}
