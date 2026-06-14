import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../../core/components/overlay_kit.dart';
import '../game/snake_flame_game.dart';

/// HUD: сверху счёт/рекорд/комбо и компактная статистика (длина, скорость и FPS
/// в debug-сборке) — всё вверху, низ оставлен свободным под экранные контролы.
class SnakeHud extends StatelessWidget {
  const SnakeHud({super.key, required this.game, required this.best});

  final SnakeFlameGame game;
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
                  builder: (_, score, _) => _Stat(
                    label: 'СЧЁТ',
                    value: '$score',
                    color: Colors.white,
                  ),
                ),
                ValueListenableBuilder<int>(
                  valueListenable: game.combo,
                  builder: (_, combo, _) => AnimatedScale(
                    scale: combo >= 2 ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutBack,
                    child: _ComboBadge(combo: combo),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Stat(
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
            _TopReadout(game: game),
          ],
        ),
      ),
    );
  }
}

/// Компактная строка статистики под основной инфой (длина/скорость/FPS).
/// Перенесена наверх, чтобы освободить низ под экранные контролы.
class _TopReadout extends StatelessWidget {
  const _TopReadout({required this.game});

  final SnakeFlameGame game;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: Colors.white.withValues(alpha: 0.3),
      fontSize: 10.5,
      letterSpacing: 1.2,
      fontWeight: FontWeight.w700,
    );
    return AnimatedBuilder(
      animation: Listenable.merge([game.length, game.speed, game.fps]),
      builder: (_, _) {
        final parts = <String>[
          'ДЛИНА ${game.length.value}',
          'СКОРОСТЬ ×${game.speed.value.toStringAsFixed(1)}',
          if (kDebugMode) '${game.fps.value.round()} FPS',
        ];
        return Text(parts.join('   ·   '), style: style);
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.color,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 11,
            letterSpacing: 2,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _ComboBadge extends StatelessWidget {
  const _ComboBadge({required this.combo});

  final int combo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6FAE), Color(0xFFFFD54F)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'x$combo COMBO',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

/// Стартовый оверлей — тап начинает партию.
class SnakeReadyOverlay extends StatelessWidget {
  const SnakeReadyOverlay({super.key, required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return _Scrim(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🐍', style: TextStyle(fontSize: 72)),
          const SizedBox(height: 16),
          Text('Snake', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 8),
          Text(
            'Свайп — поворот • Ешь быстро ради комбо',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 28),
          _PlayButton(label: 'ИГРАТЬ', onTap: onStart),
        ],
      ),
    );
  }
}

/// Оверлей конца игры с рекордом и мгновенным рестартом.
class SnakeGameOverOverlay extends StatelessWidget {
  const SnakeGameOverOverlay({
    super.key,
    required this.score,
    required this.best,
    required this.isRecord,
    required this.onRetry,
    required this.onExit,
  });

  final int score;
  final int best;
  final bool isRecord;
  final VoidCallback onRetry;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return _Scrim(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isRecord) ...[
            const Text('🏆', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 8),
            const Text(
              'НОВЫЙ РЕКОРД!',
              style: TextStyle(
                color: Color(0xFFFFD54F),
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ] else ...[
            Text(
              'Игра окончена',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
          const SizedBox(height: 20),
          Text(
            '$score',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 64,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            'рекорд: $best',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 28),
          _PlayButton(label: 'ЕЩЁ РАЗОК', onTap: onRetry),
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

class _Scrim extends StatelessWidget {
  const _Scrim({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0E0B1A).withValues(alpha: 0.82),
      alignment: Alignment.center,
      child: child,
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF7C5CFF),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
      ),
      child: Text(label),
    );
  }
}
