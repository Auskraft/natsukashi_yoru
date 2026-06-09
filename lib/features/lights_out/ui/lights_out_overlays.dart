import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../../core/components/overlay_kit.dart';
import '../game/lights_out_flame_game.dart';

/// HUD «Lights Out»: счётчик ходов слева, оставшиеся горящие лампочки и
/// рекорд (лучшее число ходов) справа, рядом — кнопка паузы.
class LightsOutHud extends StatelessWidget {
  const LightsOutHud({super.key, required this.game, required this.best});

  final LightsOutFlameGame game;

  /// Лучшее (минимальное) число ходов; 0 — рекорда ещё нет.
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
                  valueListenable: game.moves,
                  builder: (_, m, _) => StatBlock(label: 'ХОДЫ', value: '$m'),
                ),
                ValueListenableBuilder<int>(
                  valueListenable: game.lit,
                  builder: (_, lit, _) => StatBlock(
                    label: 'ГОРИТ',
                    value: '$lit',
                    color: const Color(0xFFA78BFA),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatBlock(
                      label: 'РЕКОРД',
                      value: best > 0 ? '$best' : '—',
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
            Text(
              'Тап — переключить клетку и соседей • Погаси все',
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
