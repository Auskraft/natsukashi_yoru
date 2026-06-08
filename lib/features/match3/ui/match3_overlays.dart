import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../../core/components/overlay_kit.dart';
import '../game/match3_flame_game.dart';

/// HUD блица: счёт, рекорд, обратный таймер (краснеет под конец) и комбо.
class Match3Hud extends StatelessWidget {
  const Match3Hud({super.key, required this.game, required this.best});

  final Match3FlameGame game;
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
            ValueListenableBuilder<double>(
              valueListenable: game.timeLeft,
              builder: (_, t, _) => _TimerBar(seconds: t),
            ),
            const SizedBox(height: 8),
            Center(
              child: ValueListenableBuilder<int>(
                valueListenable: game.combo,
                builder: (_, combo, _) => ComboBadge(combo: combo, label: 'CHAIN'),
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

class _TimerBar extends StatelessWidget {
  const _TimerBar({required this.seconds});

  final double seconds;

  @override
  Widget build(BuildContext context) {
    final urgent = seconds <= 10;
    final color =
        urgent ? const Color(0xFFFF5370) : const Color(0xFF4ECDC4);
    final frac = (seconds / 60).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'ВРЕМЯ',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              seconds.ceil().toString(),
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: frac,
            minHeight: 6,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}
