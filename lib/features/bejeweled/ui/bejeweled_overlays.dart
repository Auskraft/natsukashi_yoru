import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../../core/components/overlay_kit.dart';
import '../game/bejeweled_flame_game.dart';

/// HUD: счёт, рекорд, остаток ходов и комбо за глубину каскада.
class BejeweledHud extends StatelessWidget {
  const BejeweledHud({super.key, required this.game, required this.best});

  final BejeweledFlameGame game;
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
              children: [
                ValueListenableBuilder<int>(
                  valueListenable: game.score,
                  builder: (_, score, _) =>
                      StatBlock(label: 'СЧЁТ', value: '$score'),
                ),
                ValueListenableBuilder<int>(
                  valueListenable: game.movesLeft,
                  builder: (_, moves, _) => StatBlock(
                    label: 'ХОДЫ',
                    value: '$moves',
                    color: moves <= 5
                        ? const Color(0xFFFF5370)
                        : const Color(0xFF4ECDC4),
                  ),
                ),
                StatBlock(
                  label: 'РЕКОРД',
                  value: '$best',
                  color: const Color(0xFFFFD54F),
                  alignEnd: true,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Center(
              child: ValueListenableBuilder<int>(
                valueListenable: game.combo,
                builder: (_, combo, _) =>
                    ComboBadge(combo: combo, label: 'CHAIN'),
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
