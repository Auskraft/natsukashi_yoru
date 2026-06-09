import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../../core/components/overlay_kit.dart';
import '../game/block_puzzle_flame_game.dart';

/// HUD «1010!»: счёт и рекорд сверху, справа — кнопка паузы; по центру — бейдж
/// комбо при очистке нескольких линий разом. FPS показывается только в debug.
class BlockPuzzleHud extends StatelessWidget {
  const BlockPuzzleHud({super.key, required this.game, required this.best});

  final BlockPuzzleFlameGame game;
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
                builder: (_, combo, _) =>
                    ComboBadge(combo: combo, label: 'LINES'),
              ),
            ),
            const Spacer(),
            _BottomHint(game: game),
          ],
        ),
      ),
    );
  }
}

/// Нижняя строка-подсказка по управлению (+ FPS в debug-сборке).
class _BottomHint extends StatelessWidget {
  const _BottomHint({required this.game});

  final BlockPuzzleFlameGame game;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: Colors.white.withValues(alpha: 0.35),
      fontSize: 12,
      letterSpacing: 1.2,
      fontWeight: FontWeight.w700,
    );
    final hint = Text(
      'ТЯНИ фигуру из лотка на поле',
      style: style,
      textAlign: TextAlign.center,
    );
    if (!kDebugMode) return Center(child: hint);
    return Column(
      children: [
        Center(child: hint),
        const SizedBox(height: 2),
        ValueListenableBuilder<double>(
          valueListenable: game.fps,
          builder: (_, fps, _) => Text('${fps.round()} FPS', style: style),
        ),
      ],
    );
  }
}
