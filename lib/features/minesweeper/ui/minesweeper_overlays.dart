import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../../core/components/overlay_kit.dart';
import '../game/minesweeper_flame_game.dart';

String formatTime(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// HUD: счётчик оставшихся мин и таймер.
class MinesweeperHud extends StatelessWidget {
  const MinesweeperHud({super.key, required this.game});

  final MinesweeperFlameGame game;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ValueListenableBuilder<int>(
                  valueListenable: game.minesLeft,
                  builder: (_, mines, _) =>
                      StatBlock(label: '💣 МИНЫ', value: '$mines'),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ValueListenableBuilder<int>(
                      valueListenable: game.timeSec,
                      builder: (_, t, _) => StatBlock(
                        label: 'ВРЕМЯ',
                        value: formatTime(t),
                        color: const Color(0xFF4ECDC4),
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
              'Тап — открыть • Удержание — флаг',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            if (kDebugMode) ...[
              const Spacer(),
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

/// Экран конца партии: победа (со временем и рекордом) или подрыв.
class MinesweeperEndPanel extends StatelessWidget {
  const MinesweeperEndPanel({
    super.key,
    required this.won,
    required this.seconds,
    required this.bestSeconds,
    required this.isRecord,
    required this.onRetry,
    required this.onExit,
  });

  final bool won;
  final int seconds;
  final int bestSeconds;
  final bool isRecord;
  final VoidCallback onRetry;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return GameScrim(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(won ? (isRecord ? '🏆' : '🎉') : '💥',
              style: const TextStyle(fontSize: 64)),
          const SizedBox(height: 8),
          Text(
            won ? (isRecord ? 'НОВЫЙ РЕКОРД!' : 'ПОЛЕ ОЧИЩЕНО!') : 'БУМ!',
            style: TextStyle(
              color: won ? const Color(0xFFFFD54F) : const Color(0xFFFF5370),
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          if (won) ...[
            const SizedBox(height: 20),
            Text(
              formatTime(seconds),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 56,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (bestSeconds > 0)
              Text(
                'лучшее: ${formatTime(bestSeconds)}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
              ),
          ],
          const SizedBox(height: 28),
          PlayButton(label: 'ЕЩЁ РАЗОК', onTap: onRetry),
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
