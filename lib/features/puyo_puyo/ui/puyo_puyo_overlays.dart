import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../../core/components/overlay_kit.dart';
import '../game/puyo_puyo_flame_game.dart';

/// HUD: счёт, рекорд, превью следующей пары и индикатор цепочки.
class PuyoHud extends StatelessWidget {
  const PuyoHud({super.key, required this.game, required this.best});

  final PuyoPuyoFlameGame game;
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
                ValueListenableBuilder<List<int>>(
                  valueListenable: game.next,
                  builder: (_, next, _) => _NextPair(colors: next),
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
            const SizedBox(height: 10),
            Center(
              child: ValueListenableBuilder<int>(
                valueListenable: game.chain,
                builder: (_, chain, _) =>
                    ComboBadge(combo: chain, label: 'CHAIN'),
              ),
            ),
            if (kDebugMode) ...[
              const Spacer(),
              Center(
                child: ValueListenableBuilder<double>(
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
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NextPair extends StatelessWidget {
  const _NextPair({required this.colors});

  final List<int> colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'ДАЛЕЕ',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 11,
            letterSpacing: 2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        // Спутник сверху, ось снизу — как пара входит вертикально.
        _dot(colors.length > 1 ? colors[1] : 0),
        const SizedBox(height: 2),
        _dot(colors.isNotEmpty ? colors[0] : 0),
      ],
    );
  }

  Widget _dot(int color) => Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: puyoColor(color),
          shape: BoxShape.circle,
        ),
      );
}
