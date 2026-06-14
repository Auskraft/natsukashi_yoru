import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../../core/components/overlay_kit.dart';
import '../game/sokoban_flame_game.dart';

/// HUD «Сокобана»: слева номер уровня, по центру — ящики на целях,
/// справа — счётчик ходов и кнопка паузы. FPS — только в debug-сборке.
class SokobanHud extends StatelessWidget {
  const SokobanHud({super.key, required this.game});

  final SokobanFlameGame game;

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
                  valueListenable: game.level,
                  builder: (_, lvl, _) =>
                      StatBlock(label: 'УРОВЕНЬ', value: '$lvl'),
                ),
                AnimatedBuilder(
                  animation:
                      Listenable.merge([game.boxesOnGoal, game.goalCount]),
                  builder: (_, _) => StatBlock(
                    label: '📦 ЯЩИКИ',
                    value: '${game.boxesOnGoal.value}/${game.goalCount.value}',
                    color: const Color(0xFF22D3EE),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ValueListenableBuilder<int>(
                      valueListenable: game.moves,
                      builder: (_, m, _) => StatBlock(
                        label: 'ХОДЫ',
                        value: '$m',
                        alignEnd: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    PauseButton(onTap: game.togglePause),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Толкай ящики на цели',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 8),
              ValueListenableBuilder<double>(
                valueListenable: game.fps,
                builder: (_, fps, _) => Text(
                  '${fps.round()} FPS',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Экран «уровень пройден»: число ходов, лучший результат и кнопки
/// «дальше» / «заново уровень» / «в меню».
class SokobanWonPanel extends StatelessWidget {
  const SokobanWonPanel({
    super.key,
    required this.moves,
    required this.bestMoves,
    required this.isRecord,
    required this.hasNext,
    required this.onNext,
    required this.onRestart,
    required this.onExit,
  });

  final int moves;
  final int bestMoves;
  final bool isRecord;
  final bool hasNext;
  final VoidCallback onNext;
  final VoidCallback onRestart;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return GameScrim(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(isRecord ? '🏆' : '🎉', style: const TextStyle(fontSize: 64)),
          const SizedBox(height: 8),
          Text(
            isRecord ? 'НОВЫЙ РЕКОРД!' : 'УРОВЕНЬ ПРОЙДЕН!',
            style: const TextStyle(
              color: Color(0xFFFFD54F),
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '$moves',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 56,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            'ходов',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
          ),
          if (bestMoves > 0)
            Text(
              'лучшее: $bestMoves',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          const SizedBox(height: 28),
          PlayButton(
            label: hasNext ? 'ДАЛЬШЕ' : 'СНАЧАЛА',
            onTap: onNext,
          ),
          TextButton(
            onPressed: onRestart,
            child: Text(
              'Заново уровень',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          ),
          TextButton(
            onPressed: onExit,
            child: Text(
              'В меню',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          ),
        ],
      ),
    );
  }
}
