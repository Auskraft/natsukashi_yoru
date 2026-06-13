import 'package:flutter/material.dart';

import '../../../core/components/overlay_kit.dart';
import '../game/tanks_flame_game.dart';

/// HUD боя: счёт, осталось врагов, жизни и кнопка паузы.
class TanksHud extends StatelessWidget {
  const TanksHud({super.key, required this.game});

  final TanksFlameGame game;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ValueListenableBuilder<int>(
              valueListenable: game.score,
              builder: (_, v, _) => StatBlock(label: 'СЧЁТ', value: '$v'),
            ),
            const Spacer(),
            ValueListenableBuilder<int>(
              valueListenable: game.enemiesLeft,
              builder: (_, v, _) => StatBlock(
                label: 'ВРАГИ',
                value: '$v',
                color: const Color(0xFFFF8A8A),
              ),
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ValueListenableBuilder<int>(
                  valueListenable: game.lives,
                  builder: (_, v, _) => _Hearts(lives: v),
                ),
                const SizedBox(height: 8),
                PauseButton(onTap: game.togglePause),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Жизни игрока значками-танками.
class _Hearts extends StatelessWidget {
  const _Hearts({required this.lives});

  final int lives;

  @override
  Widget build(BuildContext context) {
    final n = lives.clamp(0, 5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < n; i++)
          const Padding(
            padding: EdgeInsets.only(left: 3),
            child: Icon(Icons.shield_moon, color: Color(0xFF4ECDC4), size: 18),
          ),
      ],
    );
  }
}
